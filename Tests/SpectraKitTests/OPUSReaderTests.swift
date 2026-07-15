// Fixture provenance: see opus-ground-truth.json's `_provenance` object.
// brukeropus-example-file.0 from joshduran/brukeropus @
// af5a508cef7de8089acd27a215d644ab451257dd (examples/file.0), MIT.
// opusreader2-* from spectral-cockpit/opusreader2 @
// 96f970beb0ef92ccb3ee62fc3d8b7f27e1587c41, MIT.
import Foundation
import Testing
@testable import SpectraKit

private func fixtureData(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        ?? Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
    return try Data(contentsOf: #require(url))
}

private struct GroundTruth: Decodable {
    var npt: Int; var fxv: Double; var lxv: Double
    var firstAB: [Double]; var dxu: String
    var parameterSpotChecks: [String: String]
}

@Test func readsFixtureAgainstReferenceGroundTruth() throws {
    // The JSON also holds a `_provenance` metadata object that isn't a
    // GroundTruth; drop `_`-prefixed keys before decoding the fixtures.
    let raw = try JSONSerialization.jsonObject(
        with: fixtureData("opus-ground-truth.json")) as? [String: Any] ?? [:]
    let fixturesJSON = raw.filter { !$0.key.hasPrefix("_") }
    let truth = try JSONDecoder().decode(
        [String: GroundTruth].self,
        from: JSONSerialization.data(withJSONObject: fixturesJSON))
    #expect(!truth.isEmpty)
    for (name, expected) in truth where !name.hasPrefix("_") {
        let spectra = try OPUSReader.read(data: fixtureData(name), sourceURL: nil)
        let s = try #require(spectra.first, "\(name) produced no spectra")
        #expect(s.points.count == expected.npt)
        #expect(abs(s.points.first!.x - expected.fxv) < 1e-6 ||
                abs(s.points.first!.x - expected.lxv) < 1e-6)   // grid may be descending in x
        for (i, y) in expected.firstAB.enumerated() {
            #expect(abs(s.points[i].y - y) < 1e-9, "\(name) y[\(i)]")
        }
        for (key, value) in expected.parameterSpotChecks {
            #expect(s.parameters.contains { $0.key == key && $0.value == value }, "\(name) \(key)")
        }
    }
}

@Test func truncatedFileThrowsDescriptiveError() throws {
    let whole = try fixtureData("brukeropus-example-file.0")
    for cut in [4, 23, 100] {
        #expect(throws: OPUSError.self) {
            _ = try OPUSReader.read(data: whole.prefix(cut), sourceURL: nil)
        }
    }
    // Truncation mid-data-block must error or warn, never trap or return garbage silently.
    let midCut = whole.prefix(whole.count / 2)
    do {
        let spectra = try OPUSReader.read(data: Data(midCut), sourceURL: nil)
        #expect(spectra.allSatisfy { !$0.warnings.isEmpty })
    } catch is OPUSError {
        // also acceptable
    }
}

@Test func garbageIsNotOPUS() {
    #expect(throws: OPUSError.notOPUS) {
        _ = try OPUSReader.read(data: Data("##TITLE=nope".utf8), sourceURL: nil)
    }
}

// MARK: - Y-unit discrimination (PLF), DPF, DXU, warning caps

/// The fixtures all carry PLF=AB in their sample Acquisition block, so they
/// must report absorbance with no "assumed" fallback warning.
@Test func fixturesAreAbsorbanceWithoutAssumedWarning() throws {
    for name in ["brukeropus-example-file.0",
                 "opusreader2-629266_1TP_A-1_C1.0",
                 "opusreader2-617262_1TP_C-1_A5.0"] {
        let s = try #require(
            OPUSReader.read(data: fixtureData(name), sourceURL: nil).first, "\(name)")
        #expect(s.yUnit == .absorbance, "\(name)")
        #expect(!s.warnings.contains { $0.message.contains("assumed to be absorbance") },
                "\(name)")
    }
}

@Test func syntheticPLFTransmittanceIsTransmittance() throws {
    let s = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "TR"), sourceURL: nil).first)
    #expect(s.yUnit == .transmittance)
    #expect(!s.warnings.contains { $0.message.contains("assumed to be absorbance") })
    #expect(s.points.count == 4)
    #expect(abs(s.points[0].y - 0.1) < 1e-7)
}

@Test func syntheticMissingPLFAssumesAbsorbanceWithWarning() throws {
    let s = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: nil), sourceURL: nil).first)
    #expect(s.yUnit == .absorbance)
    #expect(s.warnings.contains { $0.message.contains("assumed to be absorbance") })
}

@Test func unsupportedDPFWarnsAndStillReadsFloat32() throws {
    let s = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "AB", dpf: 2), sourceURL: nil).first)
    #expect(s.warnings.contains { $0.message.contains("DPF") })
    #expect(s.points.count == 4)
}

@Test func unrecognizedOrMissingXUnitWarns() throws {
    let odd = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "AB", dxu: "XX"), sourceURL: nil).first)
    #expect(odd.xUnit == .other("XX"))
    #expect(odd.warnings.contains { $0.message.contains("x-unit") })

    let missing = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "AB", dxu: nil), sourceURL: nil).first)
    #expect(missing.xUnit == .other("unknown"))
    #expect(missing.warnings.contains { $0.message.contains("x-unit") })
}

@Test func directoryOutOfBoundsWarningsAreCapped() throws {
    let s = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "AB", extraOutOfBoundsEntries: 6),
                        sourceURL: nil).first)
    let oob = s.warnings.filter { $0.message.contains("out of bounds") }
    #expect(oob.count == 4)   // 3 individual + 1 summary
    #expect(oob.contains { $0.message.contains("more") })
}

@Test func syntheticPresentButUnmappedPLFReportsOtherWithDistinctWarning() throws {
    // A PLF that is present but not one we map (RF = reflectance) must be
    // reported truthfully as .other, not silently coerced to absorbance.
    let s = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "RF"), sourceURL: nil).first)
    #expect(s.yUnit == .other("RF"))
    #expect(s.warnings.contains {
        $0.message.contains("Unsupported OPUS result type 'RF'") })
    // The distinct warning must NOT masquerade as the assumed-absorbance one.
    #expect(!s.warnings.contains { $0.message.contains("assumed to be absorbance") })
}

@Test func syntheticCSFScalesYValues() throws {
    // CSF (common scaling factor) != 1 multiplies the stored float32 series.
    // Raw floats are [0.1, 0.2, 0.3, 0.4]; with CSF 2.5 they scale up.
    let s = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "AB", csf: 2.5), sourceURL: nil).first)
    #expect(s.points.count == 4)
    let expected: [Double] = [0.1, 0.2, 0.3, 0.4].map { $0 * 2.5 }
    for (i, e) in expected.enumerated() {
        #expect(abs(s.points[i].y - e) < 1e-6, "y[\(i)]")
    }
}

@Test func fixtureCapacityMismatchWarnsNamingBothCounts() throws {
    // brukeropus-example-file.0's AB block holds 4928 floats but NPT is 4927;
    // the reader now surfaces that mismatch instead of truncating silently.
    let s = try #require(
        OPUSReader.read(data: fixtureData("brukeropus-example-file.0"),
                        sourceURL: nil).first)
    #expect(s.warnings.contains {
        $0.message.contains("4928") && $0.message.contains("4927") })
}

@Test func duplicateTitlesAreDisambiguated() throws {
    // This fixture yields two spectra with identical SNM-derived titles; the
    // later one must be suffixed so sidebar/results entries stay distinct.
    let spectra = try OPUSReader.read(
        data: fixtureData("opusreader2-629266_1TP_A-1_C1.0"), sourceURL: nil)
    try #require(spectra.count >= 2, "fixture expected to yield multiple spectra")
    let titles = spectra.map(\.title)
    #expect(Set(titles).count == titles.count, "titles must be unique: \(titles)")
    #expect(titles.dropFirst().contains { $0.hasSuffix(" (2)") })
}

// MARK: - Directory location (Defect A) and parameter ownership (Defect B)

/// The directory can legally live outside the first 504 bytes (real ATR files
/// use offset 8536). Reading it from the header's directory_start field must
/// yield an identical spectrum to the inline-directory case.
@Test func directoryBeyondHeaderRegionParsesIdentically() throws {
    let inline = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "AB"), sourceURL: nil).first)
    let relocated = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "AB", directoryStart: 8536),
                        sourceURL: nil).first)
    #expect(relocated.points.count == 4)
    #expect(inline.points.count == relocated.points.count)
    for i in inline.points.indices {
        #expect(abs(inline.points[i].x - relocated.points[i].x) < 1e-9, "x[\(i)]")
        #expect(abs(inline.points[i].y - relocated.points[i].y) < 1e-9, "y[\(i)]")
    }
}

/// A directory_start pointing past EOF must fail cleanly with a malformed
/// error, never trap or read out of bounds.
@Test func directoryStartBeyondEOFThrowsMalformed() {
    var blob = makeOPUSBlob(plf: "AB")
    blob.replaceSubrange(12..<16, with: le32(UInt32(blob.count + 10_000)))
    #expect {
        _ = try OPUSReader.read(data: blob, sourceURL: nil)
    } throws: { error in
        guard case OPUSError.malformed = error else { return false }
        return true
    }
}

/// When a decoy data-status block (an interferogram's IgSm block) precedes the
/// AB Data Parameter block in directory order with a conflicting NPT, the
/// paired AB status must still own the bare `NPT` key; the decoy only appears
/// under a block-name-prefixed key.
@Test func pairedStatusBlockOwnsBareKeysOverDecoy() throws {
    let s = try #require(
        OPUSReader.read(data: makeOPUSBlob(plf: "AB", decoyIgSmNPT: 999),
                        sourceURL: nil).first)
    #expect(s.parameters.contains { $0.key == "NPT" && $0.value == "4" })
    #expect(!s.parameters.contains { $0.key == "NPT" && $0.value == "999" })
    #expect(s.parameters.contains {
        $0.key == "IgSm Data Parameter.NPT" && $0.value == "999" })
}

// MARK: - Synthetic OPUS blob builder

private func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
private func le32(_ v: UInt32) -> Data {
    Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
}
private func le64(_ v: UInt64) -> Data {
    var d = Data(); for i in 0..<8 { d.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) }
    return d
}

/// One tag/type/size/value parameter record. `value.count` must be even.
private func record(_ tag: String, type: UInt16, value: Data) -> Data {
    var d = Data(tag.utf8)   // exactly 3 ASCII chars
    d.append(0)
    d += le16(type)
    d += le16(UInt16(value.count / 2))
    d += value
    return d
}

private func paddedToWord(_ d: Data) -> Data {
    var d = d
    while d.count % 4 != 0 { d.append(0) }
    return d
}

private func dirEntry(dataType: UInt8, channelType: UInt8,
                      offset: Int, byteCount: Int) -> Data {
    var d = Data([dataType, channelType, 0, 0])
    d += le32(UInt32(byteCount / 4))
    d += le32(UInt32(offset))
    return d
}

/// A minimal, structurally valid OPUS file: header, directory, AB data-status
/// parameter block, sample Acquisition block, and an AB data block of 4 floats.
///
/// `directoryStart` relocates the directory table to a high byte offset (the
/// payload then follows the header, zero-padded up to the directory) to model
/// real files whose directory lives outside the first 504 bytes; when nil the
/// directory sits inline at byte 24. `decoyIgSmNPT` prepends an IgSm
/// data-status block (earlier than the AB status in directory order) carrying a
/// conflicting NPT, to model an interferogram channel competing for bare keys.
private func makeOPUSBlob(plf: String?, dxu: String? = "WN",
                          dpf: Int32? = nil, csf: Double = 1.0,
                          extraOutOfBoundsEntries: Int = 0,
                          directoryStart: Int? = nil,
                          decoyIgSmNPT: Int? = nil) -> Data {
    var status = Data()
    if let dpf { status += record("DPF", type: 0, value: le32(UInt32(bitPattern: dpf))) }
    status += record("NPT", type: 0, value: le32(4))
    status += record("FXV", type: 1, value: le64(Double(4000).bitPattern))
    status += record("LXV", type: 1, value: le64(Double(1000).bitPattern))
    status += record("CSF", type: 1, value: le64(csf.bitPattern))
    if let dxu { status += record("DXU", type: 2, value: Data(dxu.utf8)) }
    status += record("END", type: 0, value: Data())
    let statusBlock = paddedToWord(status)

    var acq = Data()
    if let plf { acq += record("PLF", type: 2, value: Data(plf.utf8)) }
    acq += record("END", type: 0, value: Data())
    let acqBlock = paddedToWord(acq)

    var ab = Data()
    for f: Float in [0.1, 0.2, 0.3, 0.4] { ab += le32(f.bitPattern) }

    var decoyBlock = Data()
    if let decoyIgSmNPT {
        var d = Data()
        d += record("NPT", type: 0, value: le32(UInt32(decoyIgSmNPT)))
        d += record("END", type: 0, value: Data())
        decoyBlock = paddedToWord(d)
    }

    // Entry count: optional decoy + status + acq + out-of-bounds + AB + stop.
    let entryCount = (decoyIgSmNPT != nil ? 1 : 0) + extraOutOfBoundsEntries + 4
    let inlineDirectory = directoryStart == nil
    let dirStart = directoryStart ?? 24
    // The payload sits right after the header when the directory is relocated,
    // otherwise right after the inline directory table.
    let payloadStart = inlineDirectory ? (24 + entryCount * 12) : 24
    let statusOffset = payloadStart
    let acqOffset = statusOffset + statusBlock.count
    let abOffset = acqOffset + acqBlock.count
    let decoyOffset = abOffset + ab.count

    var dir = Data()
    if decoyIgSmNPT != nil {                     // decoy first in directory order
        dir += dirEntry(dataType: 23, channelType: 8, offset: decoyOffset,
                        byteCount: decoyBlock.count)
    }
    dir += dirEntry(dataType: 31, channelType: 16, offset: statusOffset,
                    byteCount: statusBlock.count)
    dir += dirEntry(dataType: 48, channelType: 0, offset: acqOffset,
                    byteCount: acqBlock.count)
    for _ in 0..<extraOutOfBoundsEntries {       // entries pointing past EOF
        dir += dirEntry(dataType: 7, channelType: 4, offset: 1_000_000, byteCount: 4)
    }
    dir += dirEntry(dataType: 15, channelType: 16, offset: abOffset,
                    byteCount: ab.count)
    dir += dirEntry(dataType: 0, channelType: 0, offset: 0, byteCount: 0)  // stop

    let payload = statusBlock + acqBlock + ab + decoyBlock

    var blob = Data([0x0A, 0x0A, 0xFE, 0xFE])   // magic
    blob += le64(0)                             // version (double), unused
    blob += le32(UInt32(dirStart))              // directory start
    blob += le32(UInt32(entryCount))            // max blocks
    blob += le32(UInt32(entryCount))            // used blocks
    if inlineDirectory {
        blob += dir
        blob += payload
    } else {
        blob += payload
        if blob.count < dirStart { blob.append(Data(count: dirStart - blob.count)) }
        blob += dir
    }
    return blob
}
