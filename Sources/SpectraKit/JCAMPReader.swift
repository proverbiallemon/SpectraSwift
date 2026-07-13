import Foundation

public enum JCAMPError: Error, Equatable {
    case notJCAMP
    case unsupported(String)
    case malformed(String)
}

/// One ##LABEL=value record with any continuation lines folded in.
struct LDR {
    var label: String      // normalized: uppercased, spaces/dashes/underscores stripped
    var rawLabel: String   // as written, for the parameters list
    var value: String
}

public enum JCAMPReader {

    public static func read(data: Data, sourceURL: URL?) throws -> [Spectrum] {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw JCAMPError.malformed("File is not text")
        }
        let ldrs = tokenize(text)
        guard ldrs.first?.label == "TITLE" else { throw JCAMPError.notJCAMP }
        return try splitBlocks(ldrs).flatMap {
            try assemble(ldrs: $0, sourceURL: sourceURL)
        }
    }

    /// A LINK block (##BLOCKS=) wraps child TITLE..END blocks. Children are
    /// delimited by nested TITLE/END pairs; the outer wrapper itself carries
    /// no data and is dropped.
    static func splitBlocks(_ ldrs: [LDR]) -> [[LDR]] {
        guard ldrs.contains(where: { $0.label == "BLOCKS" }) else { return [ldrs] }
        var children: [[LDR]] = []
        var current: [LDR] = []
        var inChild = false
        for ldr in ldrs.dropFirst() {   // drop outer TITLE
            if ldr.label == "TITLE" {
                inChild = true; current = [ldr]
            } else if ldr.label == "END" {
                if inChild, !current.isEmpty { children.append(current) }
                inChild = false; current = []
            } else if inChild {
                current.append(ldr)
            }
        }
        return children.isEmpty ? [ldrs] : children
    }

    // MARK: tokenizing

    static func normalizeLabel(_ raw: String) -> String {
        raw.uppercased().filter { !" -_/".contains($0) }
    }

    /// Split text into LDRs. Handles CRLF/CR/LF, strips $$ comments,
    /// folds continuation lines into the current LDR's value.
    static func tokenize(_ text: String) -> [LDR] {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var ldrs: [LDR] = []
        for rawLine in unified.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let r = line.range(of: "$$") { line = String(line[..<r.lowerBound]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("##") {
                let body = line.dropFirst(2)
                let parts = body.split(separator: "=", maxSplits: 1,
                                       omittingEmptySubsequences: false)
                let rawLabel = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = parts.count > 1
                    ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                ldrs.append(LDR(label: normalizeLabel(rawLabel),
                                rawLabel: rawLabel, value: value))
            } else if !ldrs.isEmpty {
                ldrs[ldrs.count - 1].value += "\n" + line
            }
        }
        return ldrs
    }

    // MARK: assembly

    static func assemble(ldrs: [LDR], sourceURL: URL?) throws -> [Spectrum] {
        var header: [String: String] = [:]
        var parameters: [Parameter] = []
        var warnings: [SpectrumWarning] = []
        var points: [SpectrumPoint] = []
        var dataForm = DataForm.continuous
        var sawData = false

        for ldr in ldrs {
            switch ldr.label {
            case "XYDATA":
                sawData = true
                dataForm = .continuous
                let (pts, w) = try parseXYData(ldr.value, header: header)
                points = pts; warnings += w
            case "PEAKTABLE", "XYPOINTS":
                sawData = true
                dataForm = ldr.label == "PEAKTABLE" ? .peaks : .continuous
                let (pts, w) = try parsePeakTable(ldr.value, header: header)
                points = pts; warnings += w
            case "NTUPLES":
                header["NTUPLES"] = ldr.value
            case "DATATABLE":
                sawData = true
                if !points.isEmpty {
                    warnings.append(SpectrumWarning(
                        "Multiple NTUPLES data tables found; only the last is shown"))
                }
                // form line e.g. "(XY..XY), PEAKS" or "(X++(Y..Y)), XYDATA"
                let formLine = ldr.value.split(separator: "\n").first.map(String.init) ?? ""
                let isPairFormat = formLine.uppercased().contains("PEAKS")
                    || formLine.uppercased().contains("XY..XY")
                dataForm = formLine.uppercased().contains("PEAKS") ? .peaks : .continuous
                // NTUPLES ##UNITS= gives "XUNIT, YUNIT"
                if let units = header["UNITS"] {
                    let parts = units.split(separator: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    if parts.count >= 2 {
                        header["XUNITS"] = parts[0]; header["YUNITS"] = parts[1]
                    }
                }
                if isPairFormat {
                    let (pts, w) = try parsePeakTable(ldr.value, header: header)
                    points = pts; warnings += w
                } else {
                    let (pts, w) = try parseXYData(ldr.value, header: header)
                    points = pts; warnings += w
                }
            case "PAGE", "ENDNTUPLES":
                header[ldr.label] = ldr.value
            case "END":
                break
            default:
                header[ldr.label] = ldr.value
                if !ldr.value.isEmpty {
                    parameters.append(Parameter(key: ldr.rawLabel, value: ldr.value))
                }
            }
        }

        guard sawData else {
            throw JCAMPError.unsupported("No XYDATA or PEAK TABLE found")
        }

        // Data-type hint: mass spectra are peaks even via XYPOINTS.
        if (header["DATATYPE"] ?? "").uppercased().contains("MASS") {
            dataForm = .peaks
        }

        let spectrum = Spectrum(
            title: header["TITLE"] ?? "Untitled",
            origin: header["ORIGIN"] ?? "",
            owner: header["OWNER"] ?? "",
            sourceURL: sourceURL,
            xUnit: xUnit(from: header["XUNITS"] ?? ""),
            yUnit: yUnit(from: header["YUNITS"] ?? ""),
            dataForm: dataForm,
            points: points,
            parameters: parameters,
            warnings: warnings)
        return [spectrum]
    }

    static func xUnit(from s: String) -> XUnit {
        switch normalizeLabel(s) {
        case "1CM", "CM1", "1PERCM": .wavenumber
        case "NANOMETERS", "NM": .wavelengthNm
        case "MICROMETERS", "MICRONS": .wavelengthUm
        case "MZ", "MASSCHARGE", "AMU": .massCharge
        case "SECONDS", "S": .seconds
        default: .other(s.isEmpty ? "X" : s)
        }
    }

    static func yUnit(from s: String) -> YUnit {
        switch normalizeLabel(s) {
        case "TRANSMITTANCE": .transmittance
        case "ABSORBANCE": .absorbance
        case "RELATIVEINTENSITY", "RELATIVEABUNDANCE": .relativeIntensity
        default: .other(s.isEmpty ? "Y" : s)
        }
    }

    static func headerDouble(_ header: [String: String], _ key: String) -> Double? {
        header[key].flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    /// value = variable list on first line, data lines after.
    static func parseXYData(_ value: String, header: [String: String])
        throws -> ([SpectrumPoint], [SpectrumWarning]) {
        var warnings: [SpectrumWarning] = []
        let lines = value.split(separator: "\n").map(String.init)
        guard let form = lines.first,
              normalizeLabel(form).contains("X") else {
            throw JCAMPError.malformed("XYDATA missing variable list")
        }
        let xFactor = headerDouble(header, "XFACTOR") ?? 1
        let yFactor = headerDouble(header, "YFACTOR") ?? 1
        let firstX = headerDouble(header, "FIRSTX")
        let lastX = headerDouble(header, "LASTX")
        let nPoints = headerDouble(header, "NPOINTS")
            .flatMap { $0.isFinite && $0 >= 0 && $0 < 1e12 ? Int($0) : nil }

        // Per-point x-increment from header, refined below if computable.
        var deltaX = headerDouble(header, "DELTAX") ?? 0
        if let f = firstX, let l = lastX, let n = nPoints, n > 1 {
            deltaX = (l - f) / Double(n - 1)
        }

        var ys: [Double] = []
        var xs: [Double] = []
        var prevEndedInDIF = false
        var runningY: Double? = nil
        var warnedNoDeltaX = false

        for line in lines.dropFirst() {
            var decoded = try ASDFDecoder.decodeLine(line, previousY: runningY)
            if prevEndedInDIF {
                // First Y is a checkpoint duplicating the running Y.
                if let expected = runningY, let got = decoded.ys.first,
                   !got.isNaN, abs(got - expected) > max(1, abs(expected)) * 1e-6 {
                    warnings.append(SpectrumWarning(
                        "DIF checkpoint mismatch at x=\(decoded.x): expected \(expected), got \(got)"))
                }
                if decoded.ys.isEmpty {
                    warnings.append(SpectrumWarning(
                        "Missing DIF checkpoint value on line starting \(decoded.x)"))
                } else {
                    decoded.ys.removeFirst()
                }
            }
            if deltaX == 0, decoded.ys.count > 1, !warnedNoDeltaX {
                warnedNoDeltaX = true
                warnings.append(SpectrumWarning(
                    "Cannot determine x spacing (no FIRSTX/LASTX/NPOINTS or DELTAX); multi-value lines share their line's X"))
            }
            // Consistency: line's X (scaled) should be ~ next expected X.
            if !xs.isEmpty, deltaX != 0 {
                let expectedX = (firstX ?? 0) + Double(xs.count) * deltaX
                if abs(decoded.x * xFactor - expectedX) > abs(deltaX) {
                    warnings.append(SpectrumWarning(
                        "X checkpoint off at line starting \(decoded.x)"))
                }
            }
            for y in decoded.ys {
                let x = (firstX ?? decoded.x * xFactor) + Double(xs.count) * deltaX
                xs.append(deltaX != 0 ? x : decoded.x * xFactor)
                ys.append(y * yFactor)
            }
            runningY = decoded.ys.last.map { _ in
                // running Y is in *raw* (unscaled) units for checkpoint math
                (ys.last ?? 0) / yFactor
            } ?? runningY
            prevEndedInDIF = decoded.endedInDIF
        }

        if let n = nPoints, n != ys.count {
            warnings.append(SpectrumWarning(
                "NPOINTS says \(n) but file contains \(ys.count) points"))
        }
        let pts = zip(xs, ys).filter { !$0.1.isNaN }
            .map { SpectrumPoint(x: $0, y: $1) }
        return (pts, warnings)
    }

    /// (XY..XY) pairs: "x1,y1 x2,y2 ..." possibly across lines.
    static func parsePeakTable(_ value: String, header: [String: String])
        throws -> ([SpectrumPoint], [SpectrumWarning]) {
        let xFactor = headerDouble(header, "XFACTOR") ?? 1
        let yFactor = headerDouble(header, "YFACTOR") ?? 1
        var pts: [SpectrumPoint] = []
        let lines = value.split(separator: "\n").dropFirst() // skip "(XY..XY)"
        for line in lines {
            // pairs separated by spaces or semicolons; x,y separated by comma
            for pair in line.split(whereSeparator: { $0 == " " || $0 == ";" || $0 == "\t" }) {
                let nums = pair.split(separator: ",").compactMap { Double($0) }
                guard nums.count == 2 else {
                    throw JCAMPError.malformed("Bad peak pair '\(pair)'")
                }
                pts.append(SpectrumPoint(x: nums[0] * xFactor, y: nums[1] * yFactor))
            }
        }
        return (pts, [])
    }
}
