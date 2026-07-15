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
