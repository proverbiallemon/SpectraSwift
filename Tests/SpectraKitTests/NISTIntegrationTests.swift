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
}

@Test func readsNISTBenzeneMS() throws {
    let s = try #require(try JCAMPReader.read(
        data: try fixture("benzene-ms.jdx"), sourceURL: nil).first)
    #expect(s.dataForm == .peaks)
    #expect(s.xUnit == .massCharge)
    #expect(s.points.contains { abs($0.x - 78) < 0.5 })  // benzene M+ = 78
}

@Test func readsNISTBenzeneUV() throws {
    let s = try #require(try JCAMPReader.read(
        data: try fixture("benzene-uv.jdx"), sourceURL: nil).first)
    #expect(s.dataForm == .continuous)
    #expect(s.points.count > 10)
}

@Test func readsNISTWaterIR() throws {
    let s = try #require(try JCAMPReader.read(
        data: try fixture("water-ir.jdx"), sourceURL: nil).first)
    #expect(s.points.count > 100)
}
