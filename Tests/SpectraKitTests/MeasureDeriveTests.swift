import Testing
import Foundation
@testable import SpectraKit

private func spec(_ title: String, xUnit: XUnit = .wavenumber,
                  yUnit: YUnit = .absorbance,
                  _ pts: [(Double, Double)]) -> Spectrum {
    Spectrum(title: title, origin: "", owner: "", sourceURL: nil,
             xUnit: xUnit, yUnit: yUnit, dataForm: .continuous,
             points: pts.map { SpectrumPoint(x: $0.0, y: $0.1) },
             parameters: [], warnings: [])
}

@Test func subtractsOnAsGridOverOverlap() throws {
    let a = spec("A", [(0, 5), (1, 5), (2, 5), (3, 5), (4, 5)])
    let b = spec("B", [(1, 1), (3, 3)])   // linear 1→3 over x 1→3
    let d = try Measure.subtract(a, minus: b)
    #expect(d.title == "A − B")
    // Overlap is x ∈ [1, 3]; b interpolates to 1, 2, 3 there.
    #expect(d.points == [SpectrumPoint(x: 1, y: 4),
                         SpectrumPoint(x: 2, y: 3),
                         SpectrumPoint(x: 3, y: 2)])
    #expect(d.warnings.contains { $0.message.contains("overlap") })
}

@Test func subtractFullOverlapHasNoWarning() throws {
    let a = spec("A", [(0, 5), (1, 5), (2, 5)])
    let b = spec("B", [(0, 1), (2, 1)])
    let d = try Measure.subtract(a, minus: b)
    #expect(d.points.count == 3)
    #expect(d.warnings.isEmpty)
}

@Test func subtractRejectsDisjointRanges() {
    let a = spec("A", [(0, 1), (1, 1)])
    let b = spec("B", [(10, 1), (11, 1)])
    #expect(throws: MeasureError.noOverlap) {
        _ = try Measure.subtract(a, minus: b)
    }
}

@Test func convertsMicrometersToWavenumber() throws {
    let um = spec("CFC", xUnit: .wavelengthUm, [(2.0, 0.8), (4.0, 0.5), (10.0, 0.2)])
    let wn = try #require(um.convertedToWavenumber())
    #expect(wn.xUnit == .wavenumber)
    // 10000/x, re-sorted ascending: 10µm→1000, 4µm→2500, 2µm→5000
    #expect(wn.points == [SpectrumPoint(x: 1000, y: 0.2),
                          SpectrumPoint(x: 2500, y: 0.5),
                          SpectrumPoint(x: 5000, y: 0.8)])
    #expect(wn.warnings.contains { $0.message.contains("µm") })
}

@Test func conversionRefusedForOtherUnits() {
    let wn = spec("IR", xUnit: .wavenumber, [(400, 1)])
    #expect(wn.convertedToWavenumber() == nil)
}

@Test func conversionSkipsNonPositiveX() throws {
    let um = spec("BAD", xUnit: .wavelengthUm, [(0.0, 1), (2.0, 0.5)])
    let wn = try #require(um.convertedToWavenumber())
    #expect(wn.points == [SpectrumPoint(x: 5000, y: 0.5)])
}

@Test func subtractRefusesMismatchedXUnits() {
    let ir = spec("IR", xUnit: .wavenumber, [(200, 1), (800, 1)])
    let uv = spec("UV", xUnit: .wavelengthNm, [(200, 1), (800, 1)])
    #expect(throws: MeasureError.unitMismatch) {
        _ = try Measure.subtract(ir, minus: uv)
    }
}

@Test func subtractConvertsMicrometerOperand() throws {
    let ir = spec("IR", xUnit: .wavenumber, [(1000, 5), (2500, 5), (5000, 5)])
    let um = spec("UM", xUnit: .wavelengthUm, [(2.0, 1), (4.0, 1), (10.0, 1)])
    // µm operand converts to wavenumber 1000/2500/5000 with y=1 → d = 4 everywhere.
    let d = try Measure.subtract(ir, minus: um)
    #expect(d.points.map(\.y).allSatisfy { abs($0 - 4) < 1e-9 })
    #expect(d.points.count == 3)
}

@Test func subtractWarnsOnMixedYUnits() throws {
    let a = spec("A", yUnit: .absorbance, [(0, 5), (1, 5)])
    let b = spec("B", yUnit: .transmittance, [(0, 1), (1, 1)])
    let d = try Measure.subtract(a, minus: b)
    #expect(d.warnings.contains { $0.message.contains("different y-units") })
}
