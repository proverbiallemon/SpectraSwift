import Testing
@testable import SpectraKit

@Test func spectrumBasics() {
    let s = Spectrum(
        title: "BENZENE",
        origin: "NIST",
        owner: "NIST",
        sourceURL: nil,
        xUnit: .wavenumber,
        yUnit: .transmittance,
        dataForm: .continuous,
        points: [SpectrumPoint(x: 400, y: 0.9), SpectrumPoint(x: 4000, y: 0.1)],
        parameters: [Parameter(key: "TITLE", value: "BENZENE")],
        warnings: []
    )
    #expect(s.xRange == 400...4000)
    #expect(s.yRange == 0.1...0.9)
    #expect(s.points.count == 2)
}

@Test func emptySpectrumRanges() {
    let s = Spectrum(
        title: "EMPTY", origin: "", owner: "", sourceURL: nil,
        xUnit: .other("ARBITRARY"), yUnit: .other("ARBITRARY"),
        dataForm: .continuous, points: [], parameters: [], warnings: []
    )
    #expect(s.xRange == nil)
    #expect(s.yRange == nil)
}
