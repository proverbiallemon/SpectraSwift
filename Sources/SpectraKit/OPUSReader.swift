import Foundation

public enum OPUSError: Error, Equatable {
    case notOPUS
    case malformed(String)
    case noSpectrumData(found: [String])
}

/// Reads Bruker OPUS binary spectrum files (`.0`, `.1`, ...). OPUS files are
/// little-endian throughout: a 24-byte header, a flat directory of 12-byte
/// entries, then a set of "blocks" the entries point at. Blocks are either
/// parameter blocks (tag/type/size/value records) or raw float32 data series.
/// A result absorbance ("AB") data block is paired with its data-status
/// parameter block, which supplies NPT/FXV/LXV/DXU/CSF for assembly.
///
/// Every offset and length taken from the file is bounds-checked before use;
/// a truncated or hostile file throws a descriptive `OPUSError`, never traps.
public enum OPUSReader {
    static let magic: [UInt8] = [0x0A, 0x0A, 0xFE, 0xFE]
    static let headerLength = 24
    static let directoryLimit = 504    // HEADER_LEN: entries live in the first 504 bytes.
    static let entrySize = 12

    /// Block type codes (the `dataType` byte of a directory entry).
    static let dataTypeAB = 15         // result spectrum series
    static let dataTypeABParam = 31    // "AB Data Parameter" (data-status for AB)

    /// One directory entry plus the human-readable name of the block it points at.
    struct Block {
        var dataType: Int
        var channelType: Int
        var textType: Int
        var byteCount: Int   // payload length in bytes (chunk_size * 4)
        var offset: Int      // absolute byte offset of the payload
        var name: String
    }

    /// A parsed parameter value. `display` is the canonical string form used
    /// for the parameters list and ground-truth spot checks.
    enum OPUSValue: Equatable {
        case int(Int)
        case double(Double)
        case string(String)

        var display: String {
            switch self {
            case .int(let v): return String(v)
            case .double(let v):
                // Integers-as-doubles print without a trailing ".0"; keep full
                // precision otherwise so numeric parameters round-trip.
                if v == v.rounded() && abs(v) < 1e15 {
                    return String(Int(v))
                }
                return String(v)
            case .string(let s): return s
            }
        }
    }

    public static func read(data: Data, sourceURL: URL?) throws -> [Spectrum] {
        guard data.count >= headerLength, Array(data.prefix(4)) == magic else {
            throw OPUSError.notOPUS
        }

        var warnings: [SpectrumWarning] = []
        let blocks = try parseDirectory(data, warnings: &warnings)

        // Parse every parameter block once, keyed by its position in `blocks`.
        var paramBlocks: [Int: [String: OPUSValue]] = [:]
        for (i, block) in blocks.enumerated() where block.isParameterBlock {
            do {
                let (values, w) = try parseParameterBlock(data, block: block)
                paramBlocks[i] = values
                warnings += w
            } catch let OPUSError.malformed(reason) {
                warnings.append(SpectrumWarning(
                    "Skipped unreadable \(block.name) block: \(reason)"))
            }
        }

        // Find AB data blocks and pair each with a data-status parameter block.
        // Order by descending file offset so the primary (final) result comes
        // first: OPUS writes the final AB result after any intermediate one,
        // and the reference oracles resolve the primary the same way. The test
        // harness reads `spectra.first`, so this ordering matters.
        let abBlockIndices = blocks.indices
            .filter { blocks[$0].dataType == dataTypeAB }
            .sorted { blocks[$0].offset > blocks[$1].offset }
        guard !abBlockIndices.isEmpty else {
            throw OPUSError.noSpectrumData(found: blocks.map(\.name))
        }
        let statusIndices = blocks.indices.filter { blocks[$0].dataType == dataTypeABParam }

        var spectra: [Spectrum] = []
        for abIndex in abBlockIndices {
            let ab = blocks[abIndex]
            guard let statusIndex = pairStatusBlock(for: ab,
                                                    among: statusIndices,
                                                    blocks: blocks),
                  let status = paramBlocks[statusIndex] else {
                warnings.append(SpectrumWarning(
                    "AB data block at offset \(ab.offset) has no data-status parameters; skipped"))
                continue
            }
            let spectrum = try assemble(
                data: data, abBlock: ab, status: status,
                allParams: blocks.indices.compactMap { i in
                    paramBlocks[i].map { (blocks[i].name, $0) }
                },
                sourceURL: sourceURL, sharedWarnings: warnings)
            spectra.append(spectrum)
        }

        guard !spectra.isEmpty else {
            throw OPUSError.noSpectrumData(found: blocks.map(\.name))
        }
        disambiguateTitles(&spectra)
        return spectra
    }

    /// When one file yields several spectra sharing a title (multi-AB files
    /// whose SNM is identical), suffix the second and later occurrences with
    /// " (2)", " (3)", ... so sidebar and results-table entries stay
    /// distinguishable. The first occurrence keeps its bare title.
    static func disambiguateTitles(_ spectra: inout [Spectrum]) {
        var seen: [String: Int] = [:]
        for i in spectra.indices {
            let base = spectra[i].title
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            if n > 1 {
                spectra[i].title = "\(base) (\(n))"
            }
        }
    }

    // MARK: - Directory

    /// Walk the 12-byte directory entries from byte 24. Stops at the 504-byte
    /// limit, an offset of 0, or the first entry that runs past the file. An
    /// entry whose payload is out of bounds is skipped with a warning; if NO
    /// valid block is ever found the file is malformed.
    static func parseDirectory(_ data: Data, warnings: inout [SpectrumWarning]) throws -> [Block] {
        var blocks: [Block] = []
        // Prefer the directory_start field (int32 LE at byte 12) over the
        // hardcoded 24; every real file agrees but the field is authoritative.
        let dirStart = readUInt32(data, at: 12).map(Int.init) ?? headerLength
        var cursor = (dirStart > 0 && dirStart <= directoryLimit) ? dirStart : headerLength
        var outOfBoundsCount = 0

        while cursor + entrySize <= directoryLimit && cursor + entrySize <= data.count {
            guard let dataType = readUInt8(data, at: cursor),
                  let channelType = readUInt8(data, at: cursor + 1),
                  let textType = readUInt8(data, at: cursor + 2),
                  let chunkWords = readUInt32(data, at: cursor + 4),
                  let offset32 = readUInt32(data, at: cursor + 8) else {
                break
            }
            let offset = Int(offset32)
            if offset <= 0 { break }
            // chunkWords is a UInt32; multiplying into Int can't overflow on
            // 64-bit but guard the byte extent against the file length.
            let byteCount = Int(chunkWords) * 4
            if offset + byteCount > data.count {
                // Truncated or corrupt entry: record it (capped at 3 plus a
                // summary, the JCAMPReader idiom), keep scanning others.
                outOfBoundsCount += 1
                if outOfBoundsCount <= 3 {
                    warnings.append(SpectrumWarning(
                        "Directory entry out of bounds (offset \(offset), \(byteCount) bytes), skipped"))
                }
                cursor += entrySize
                continue
            }
            blocks.append(Block(dataType: Int(dataType),
                                channelType: Int(channelType),
                                textType: Int(textType),
                                byteCount: byteCount,
                                offset: offset,
                                name: blockName(dataType: Int(dataType),
                                                channelType: Int(channelType),
                                                textType: Int(textType))))
            cursor += entrySize
        }

        if outOfBoundsCount > 3 {
            warnings.append(SpectrumWarning(
                "\(outOfBoundsCount - 3) more directory entries out of bounds, skipped"))
        }
        if blocks.isEmpty {
            throw OPUSError.malformed(
                outOfBoundsCount > 0 ? "All directory entries out of bounds"
                                     : "No readable directory entries")
        }
        return blocks
    }

    /// Names blocks the way both reference readers do, keyed on dataType then
    /// (for data / data-status blocks) channelType.
    static func blockName(dataType: Int, channelType: Int, textType: Int) -> String {
        switch dataType {
        case 0:
            switch textType {
            case 8: return "Info Block"
            case 104: return "History"
            case 152: return "Curve Fit"
            case 168: return "Signature"
            case 240: return "Integration Method"
            default: return "Text Information"
            }
        case 7: return channelSuffixName(channelType, ref: false, isData: true)
        case 11: return channelSuffixName(channelType, ref: true, isData: true)
        case 15: return "AB"
        case 23: return channelSuffixName(channelType, ref: false, isData: false)
        case 27: return channelSuffixName(channelType, ref: true, isData: false)
        case 31: return "AB Data Parameter"
        case 32: return "Instrument"
        case 40: return "Instrument (Rf)"
        case 48: return "Acquisition"
        case 56: return "Acquisition (Rf)"
        case 64: return "Fourier Transformation"
        case 72: return "Fourier Transformation (Rf)"
        case 96: return "Optik"
        case 104: return "Optik (Rf)"
        case 160: return "Sample"
        default: return "Block type \(dataType)"
        }
    }

    static func channelSuffixName(_ channelType: Int, ref: Bool, isData: Bool) -> String {
        let base: String
        switch channelType {
        case 4: base = "ScS"
        case 8: base = "IgS"
        case 12: base = "PhS"
        case 56: base = "PwS"
        default: base = "Ch\(channelType)S"
        }
        let name = base + (ref ? "Rf" : "m")
        return isData ? name : name + " Data Parameter"
    }

    /// AB data ↔ AB Data Parameter pairing. The reference oracle's naive
    /// "last name wins" is wrong on multi-AB files (see task 7 report), so pair
    /// by nearest matching status block: exactly one status block pairs
    /// trivially; otherwise choose the status block at the greatest offset not
    /// exceeding the data block's offset (each AB is written just after its
    /// status), else the closest by offset.
    static func pairStatusBlock(for ab: Block, among statusIndices: [Int],
                                blocks: [Block]) -> Int? {
        guard !statusIndices.isEmpty else { return nil }
        if statusIndices.count == 1 { return statusIndices[0] }
        let below = statusIndices.filter { blocks[$0].offset <= ab.offset }
        if let best = below.max(by: { blocks[$0].offset < blocks[$1].offset }) {
            return best
        }
        return statusIndices.min(by: {
            abs(blocks[$0].offset - ab.offset) < abs(blocks[$1].offset - ab.offset)
        })
    }

    // MARK: - Parameter blocks

    /// Parse a tag/type/size/value parameter block. Records: 3 ASCII bytes +
    /// NUL tag, int16 LE type at +4 (0 = int32, 1 = float64, else NUL-terminated
    /// Latin-1 string), int16 LE size at +6 in 2-byte words, value at +8. Stops
    /// at the "END" tag or the block's end.
    static func parseParameterBlock(_ data: Data, block: Block)
        throws -> ([String: OPUSValue], [SpectrumWarning]) {
        var values: [String: OPUSValue] = [:]
        var warnings: [SpectrumWarning] = []
        var unknownTypeCount = 0
        let start = block.offset
        let end = block.offset + block.byteCount
        guard end <= data.count else {
            throw OPUSError.malformed("parameter block runs past end of file")
        }
        var cursor = start

        while cursor + 8 <= end {
            guard let tag = readTag(data, at: cursor) else { break }
            if tag == "END" { break }
            guard let typeCode = readUInt16(data, at: cursor + 4),
                  let sizeWords = readUInt16(data, at: cursor + 6) else { break }
            let valueLength = Int(sizeWords) * 2
            let valueStart = cursor + 8
            let valueEnd = valueStart + valueLength
            guard valueEnd <= end else {
                warnings.append(SpectrumWarning(
                    "Parameter \(tag) in \(block.name) runs past block end; stopped"))
                break
            }

            switch typeCode {
            case 0:
                if let v = readInt32(data, at: valueStart) {
                    values[tag] = .int(Int(v))
                }
            case 1:
                if let v = readFloat64(data, at: valueStart) {
                    values[tag] = .double(v)
                }
            default:
                // 2/3/4 (and any other non-0/1) are strings: Latin-1, truncated
                // at the first NUL. Decode Latin-1 unconditionally for byte-for-
                // byte parity with the ground truth (do not honor CPG).
                values[tag] = .string(readLatin1String(data, from: valueStart, to: valueEnd))
                if typeCode > 4 {
                    unknownTypeCount += 1
                    if unknownTypeCount <= 3 {
                        warnings.append(SpectrumWarning(
                            "Unknown parameter type \(typeCode) for \(tag); read as string"))
                    }
                }
            }
            cursor = valueEnd
        }

        if unknownTypeCount > 3 {
            warnings.append(SpectrumWarning(
                "\(unknownTypeCount - 3) more parameters had unknown types"))
        }
        return (values, warnings)
    }

    // MARK: - Assembly

    static func assemble(data: Data, abBlock: Block, status: [String: OPUSValue],
                         allParams: [(String, [String: OPUSValue])],
                         sourceURL: URL?, sharedWarnings: [SpectrumWarning]) throws -> Spectrum {
        var warnings = sharedWarnings

        guard let npt = status["NPT"]?.intValue, npt >= 2 else {
            throw OPUSError.malformed("AB data-status block has no usable NPT")
        }
        guard let fxv = status["FXV"]?.doubleValue,
              let lxv = status["LXV"]?.doubleValue else {
            throw OPUSError.malformed("AB data-status block missing FXV/LXV")
        }

        // DPF (Data Point Format): 1 = float32, 2 = int32. Only float32 is
        // implemented; a different DPF must never be read silently as floats.
        if let dpf = status["DPF"]?.intValue, dpf != 1 {
            warnings.append(SpectrumWarning(
                "Unsupported OPUS data point format (DPF=\(dpf)); values read as float32"))
        }

        // Y values: float32 LE array in the data block. Read exactly NPT values
        // when the block holds at least that many; when it holds FEWER, read
        // what is there. Never read past the block. Any mismatch between block
        // capacity and NPT (in either direction) is worth a warning: a smaller
        // block means truncation, a larger one means trailing floats we ignore.
        let capacity = abBlock.byteCount / 4
        let count = min(npt, capacity)
        if capacity != npt {
            warnings.append(SpectrumWarning(
                "OPUS data block holds \(capacity) values but NPT says \(npt); read \(count)"))
        }

        let csf = status["CSF"]?.doubleValue
        let applyCSF = csf.map { $0 != 1 && $0.isFinite } ?? false
        let scale = applyCSF ? csf! : 1

        var ys: [Double] = []
        ys.reserveCapacity(count)
        for i in 0..<count {
            guard let f = readFloat32(data, at: abBlock.offset + i * 4) else {
                throw OPUSError.malformed("AB data block truncated at point \(i)")
            }
            ys.append(applyCSF ? Double(f) * scale : Double(f))
        }

        // Grid: x_i = fxv + (lxv - fxv) * i / (npt - 1). npt (not count) sets
        // the spacing so the x-axis matches the instrument grid even if the
        // stored series was padded or truncated.
        let step = (lxv - fxv) / Double(npt - 1)
        var points: [SpectrumPoint] = []
        points.reserveCapacity(ys.count)
        for (i, y) in ys.enumerated() {
            points.append(SpectrumPoint(x: fxv + step * Double(i), y: y))
        }

        let dxu = status["DXU"]?.stringValue ?? ""
        let xUnit = xUnit(from: dxu, warnings: &warnings)

        // Y-unit: PLF ("Result Spectrum") in the sample Acquisition block names
        // the stored result kind (AB = absorbance, TR = transmittance). Only
        // the sample block counts; the "Acquisition (Rf)" twin describes the
        // reference channel and can legitimately disagree (e.g. TR while the
        // result is AB). A PLF that is present but unmapped (e.g. RF
        // reflectance, KM Kubelka-Munk) is reported truthfully as .other with a
        // distinct warning; a missing or empty PLF falls back to absorbance
        // with the assumed warning so neither case is ever silent.
        let plf = (allParams.first { $0.0 == "Acquisition" }?.1["PLF"]?.stringValue)?
            .trimmingCharacters(in: .whitespaces).uppercased()
        let yUnit: YUnit
        switch plf {
        case "AB": yUnit = .absorbance
        case "TR": yUnit = .transmittance
        case .some(let raw) where !raw.isEmpty:
            yUnit = .other(raw)
            warnings.append(SpectrumWarning(
                "Unsupported OPUS result type '\(raw)'; y-axis may not be meaningful for display conversions"))
        default:
            yUnit = .absorbance
            warnings.append(SpectrumWarning("OPUS result block assumed to be absorbance"))
        }

        // Collect parameters. Blocks are visited in file (directory) order, in
        // which the sample/primary channel precedes its reference (Rf) twin.
        // The first block to carry a key owns the bare key name; a later block
        // repeating the same value is dropped (the common sample/reference
        // duplicate, e.g. INS in Instrument and Instrument (Rf)). A later block
        // with a genuinely DIFFERENT value is kept, block-name-prefixed, so no
        // data is lost (e.g. "Acquisition (Rf).PLF" when the reference channel
        // is transmittance while the sample result is absorbance).
        var parameters: [Parameter] = []
        var bareValueForKey: [String: String] = [:]
        var snm: String?
        var ins: String?
        for (blockName, block) in allParams {
            for (key, value) in block.sortedForStableOrder {
                if key == "SNM", snm == nil, case .string(let s) = value, !s.isEmpty {
                    snm = s
                }
                if key == "INS", ins == nil, case .string(let s) = value, !s.isEmpty {
                    ins = s
                }
                let display = value.display
                if let existing = bareValueForKey[key] {
                    if existing != display {
                        parameters.append(Parameter(key: "\(blockName).\(key)", value: display))
                    }
                    // Same value in a later block: drop the duplicate.
                } else {
                    bareValueForKey[key] = display
                    parameters.append(Parameter(key: key, value: display))
                }
            }
        }

        let title = snm?.nonEmpty
            ?? sourceURL?.deletingPathExtension().lastPathComponent
            ?? "OPUS spectrum"

        return Spectrum(
            title: title,
            origin: ins ?? "",
            owner: "",
            sourceURL: sourceURL,
            xUnit: xUnit,
            yUnit: yUnit,
            dataForm: .continuous,
            points: points,
            parameters: parameters,
            warnings: warnings)
    }

    static func xUnit(from dxu: String, warnings: inout [SpectrumWarning]) -> XUnit {
        switch dxu.uppercased() {
        case "WN": return .wavenumber
        case "MI": return .wavelengthUm
        case "":
            warnings.append(SpectrumWarning("OPUS x-unit (DXU) missing"))
            return .other("unknown")
        default:
            warnings.append(SpectrumWarning("Unrecognized OPUS x-unit '\(dxu)'"))
            return .other(dxu)
        }
    }

    // MARK: - Bounds-checked little-endian loads

    /// All loads validate their range against `data` and return nil on a bad
    /// range, so callers never trap. `data` may be a slice; we normalize to the
    /// slice's own index space with `startIndex`.

    static func readUInt8(_ data: Data, at index: Int) -> UInt8? {
        guard index >= 0, index < data.count else { return nil }
        return data[data.startIndex + index]
    }

    static func readUInt16(_ data: Data, at index: Int) -> UInt16? {
        guard index >= 0, index + 2 <= data.count else { return nil }
        let b = data.startIndex + index
        return UInt16(data[b]) | (UInt16(data[b + 1]) << 8)
    }

    static func readUInt32(_ data: Data, at index: Int) -> UInt32? {
        guard index >= 0, index + 4 <= data.count else { return nil }
        let b = data.startIndex + index
        return UInt32(data[b]) | (UInt32(data[b + 1]) << 8)
            | (UInt32(data[b + 2]) << 16) | (UInt32(data[b + 3]) << 24)
    }

    static func readInt32(_ data: Data, at index: Int) -> Int32? {
        readUInt32(data, at: index).map { Int32(bitPattern: $0) }
    }

    static func readFloat32(_ data: Data, at index: Int) -> Float? {
        readUInt32(data, at: index).map { Float(bitPattern: $0) }
    }

    static func readFloat64(_ data: Data, at index: Int) -> Double? {
        guard index >= 0, index + 8 <= data.count else { return nil }
        let b = data.startIndex + index
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(data[b + i]) << (8 * i) }
        return Double(bitPattern: bits)
    }

    /// 3-char ASCII tag at `index`; nil if the bytes aren't printable ASCII.
    static func readTag(_ data: Data, at index: Int) -> String? {
        guard index >= 0, index + 3 <= data.count else { return nil }
        let b = data.startIndex + index
        var scalars: [Character] = []
        for i in 0..<3 {
            let byte = data[b + i]
            if byte == 0 { break }
            guard byte >= 0x20, byte < 0x7F else { return nil }
            scalars.append(Character(UnicodeScalar(byte)))
        }
        return scalars.isEmpty ? nil : String(scalars)
    }

    /// Latin-1 decode of `[from, to)`, truncated at the first NUL byte.
    static func readLatin1String(_ data: Data, from: Int, to: Int) -> String {
        guard from >= 0, from <= to, to <= data.count else { return "" }
        let base = data.startIndex
        var scalars = String.UnicodeScalarView()
        for i in from..<to {
            let byte = data[base + i]
            if byte == 0 { break }
            scalars.append(UnicodeScalar(byte))   // Latin-1: byte == code point
        }
        return String(scalars)
    }
}

private extension OPUSReader.Block {
    var isParameterBlock: Bool {
        switch dataType {
        case 23, 27, 31, 32, 40, 48, 56, 64, 72, 96, 104, 160:
            return true
        case 0:
            return textType == 8   // Info Block is parsed as parameters.
        default:
            return false
        }
    }
}

private extension OPUSReader.OPUSValue {
    var intValue: Int? {
        switch self {
        case .int(let v): return v
        // Guard the Double->Int conversion: Int(v) traps on a non-finite or
        // out-of-range value, and NPT is file-derived, so a hostile file that
        // stored it as a wild float64 must not crash the reader.
        case .double(let v):
            guard v.isFinite, v >= -9.0e18, v <= 9.0e18 else { return nil }
            return Int(v)
        case .string(let s): return Int(s)
        }
    }
    var doubleValue: Double? {
        switch self {
        case .int(let v): return Double(v)
        case .double(let v): return v
        case .string(let s): return Double(s)
        }
    }
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

private extension Dictionary where Key == String, Value == OPUSReader.OPUSValue {
    /// Deterministic key order so the parameters list is stable across runs.
    var sortedForStableOrder: [(String, OPUSReader.OPUSValue)] {
        keys.sorted().map { ($0, self[$0]!) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
