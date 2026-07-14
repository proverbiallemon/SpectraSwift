import Testing
import Foundation
@testable import SpectraKit

private func fixture(_ name: String) throws -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
        ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
    guard let url else { throw JCAMPError.malformed("missing fixture \(name)") }
    return try Data(contentsOf: url)
}

@Test func readsNISTBenzeneIR() throws {
    let spectra = try JCAMPReader.read(data: try fixture("benzene-ir.jdx"), sourceURL: nil)
    let s = try #require(spectra.first)
    #expect(s.xUnit == .wavenumber)
    #expect(s.dataForm == .continuous)
    #expect(s.points.count > 500)                 // real IR traces are dense
    let xr = try #require(s.xRange)
    #expect(xr.lowerBound > 300 && xr.upperBound < 5000)
    // No hard checkpoint failures allowed on a clean NIST file:
    #expect(s.warnings.filter { $0.message.contains("checkpoint mismatch") }.isEmpty)

    // Pin exact first/last points against the fixture header + first data line:
    // ##FIRSTX=450.0 ##LASTX=3966.0 ##YFACTOR=0.000149658
    // 450.0 221 151 188 110 141 123 232 95 213 43  -> first raw Y = 221
    // 221 * 0.000149658 = 0.033074418
    let first = try #require(s.points.first)
    let last = try #require(s.points.last)
    #expect(abs(first.x - 450.0) < 450.0 * 1e-6)
    #expect(abs(first.y - 0.033074418) < 1e-9)
    #expect(abs(last.x - 3966.0) < 3966.0 * 1e-6)
    // FIRSTX < LASTX, so x must be strictly ascending.
    #expect(zip(s.points, s.points.dropFirst()).allSatisfy { $0.x < $1.x })
}

@Test func readsNISTBenzeneMS() throws {
    let s = try #require(try JCAMPReader.read(
        data: try fixture("benzene-ms.jdx"), sourceURL: nil).first)
    #expect(s.dataForm == .peaks)
    #expect(s.xUnit == .massCharge)
    #expect(s.points.contains { abs($0.x - 78) < 0.5 })  // benzene M+ = 78

    // Pin the base peak: ##MAXY=9999, and the peak table's largest value is
    // "78,9999" (##FIRSTX=15 ##LASTX=79, XFACTOR=YFACTOR=1).
    let basePeak = try #require(s.points.max(by: { $0.y < $1.y }))
    #expect(abs(basePeak.x - 78) < 1e-9)
    #expect(abs(basePeak.y - 9999) < 1e-9)
}

@Test func readsNISTBenzeneUV() throws {
    let s = try #require(try JCAMPReader.read(
        data: try fixture("benzene-uv.jdx"), sourceURL: nil).first)
    #expect(s.dataForm == .continuous)
    #expect(s.points.count > 10)
    #expect(s.xUnit == .wavelengthNm)

    // Pin the exact first XYPOINTS pair (XFACTOR=YFACTOR=1.0):
    // ##XYPOINTS=(XY..XY)
    // 162.4180,3.703814
    let first = try #require(s.points.first)
    #expect(abs(first.x - 162.4180) < 1e-6)
    #expect(abs(first.y - 3.703814) < 1e-9)
}

@Test func readsNISTWaterIR() throws {
    let s = try #require(try JCAMPReader.read(
        data: try fixture("water-ir.jdx"), sourceURL: nil).first)
    #expect(s.points.count > 100)

    // Pin exact first/last points against the fixture header + first data line:
    // ##FIRSTX=450.0 ##LASTX=3966.0 ##YFACTOR=0.000062833
    // 450.0 97 1808 4679 1749 1382 2926 3112 759 1423 1682  -> first raw Y = 97
    // 97 * 0.000062833 = 0.006094801
    let first = try #require(s.points.first)
    let last = try #require(s.points.last)
    #expect(abs(first.x - 450.0) < 450.0 * 1e-6)
    #expect(abs(first.y - 0.006094801) < 1e-9)
    #expect(abs(last.x - 3966.0) < 3966.0 * 1e-6)
    // FIRSTX < LASTX, so x must be strictly ascending.
    #expect(zip(s.points, s.points.dropFirst()).allSatisfy { $0.x < $1.x })
}
