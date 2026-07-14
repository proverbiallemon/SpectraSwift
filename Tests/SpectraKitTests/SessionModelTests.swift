import Testing
import Foundation
@testable import SpectraKit

@Test func sessionRoundTrips() throws {
    let specID = UUID()
    let inline = SessionInlineSpectrum(
        title: "A − B", xUnit: .wavenumber, yUnit: .absorbance,
        dataForm: .continuous,
        points: [SpectrumPoint(x: 1, y: 2), SpectrumPoint(x: 3, y: 4)])
    let session = SessionFile(
        version: 1,
        spectra: [
            SessionSpectrumRef(id: specID, path: "/tmp/a.jdx", inline: nil,
                               color: SessionRGBA(r: 1, g: 0, b: 0, a: 1), isVisible: true),
            SessionSpectrumRef(id: UUID(), path: nil, inline: inline,
                               color: SessionRGBA(r: 0, g: 1, b: 0, a: 1), isVisible: false),
        ],
        peaks: [PeakMark(spectrumID: specID, x: 674, y: 0.3, height: 0.25,
                         displayMode: "As Recorded")],
        regions: [IntegrationRegion(spectrumID: specID, x1: 600, x2: 700,
                                    area: 12.5, displayMode: "As Recorded")],
        viewport: SessionViewportModel(xLo: 400, xHi: 4000, yLo: 0, yHi: 1),
        displayMode: "As Recorded", autoY: true, selectedID: specID)

    let data = try session.encoded()
    let back = try SessionFile.decode(data)
    #expect(back.spectra.count == 2)
    #expect(back.spectra[0].path == "/tmp/a.jdx")
    #expect(back.spectra[1].inline?.points.count == 2)
    #expect(back.peaks == session.peaks)
    #expect(back.regions == session.regions)
    #expect(back.viewport == session.viewport)
    #expect(back.autoY == true)
    #expect(back.selectedID == specID)
}

@Test func inlineSpectrumRebuilds() {
    let s = SessionInlineSpectrum(
        title: "T", xUnit: .other("WEIRD"), yUnit: .transmittance,
        dataForm: .peaks, points: [SpectrumPoint(x: 78, y: 9999)])
    let spectrum = s.makeSpectrum()
    #expect(spectrum.title == "T")
    #expect(spectrum.xUnit == .other("WEIRD"))
    #expect(spectrum.dataForm == .peaks)
    #expect(spectrum.points.count == 1)
    let round = SessionInlineSpectrum(from: spectrum)
    #expect(round.points == s.points)
}

@Test func decodeRejectsGarbage() {
    #expect(throws: (any Error).self) {
        _ = try SessionFile.decode(Data("not json".utf8))
    }
}

@Test func fingerprintDetectsContentChange() {
    let a = SessionInlineSpectrum(title: "T", xUnit: .wavenumber, yUnit: .absorbance,
                                  dataForm: .continuous,
                                  points: [SpectrumPoint(x: 1, y: 2)]).makeSpectrum()
    let b = SessionInlineSpectrum(title: "T", xUnit: .wavenumber, yUnit: .absorbance,
                                  dataForm: .continuous,
                                  points: [SpectrumPoint(x: 1, y: 3)]).makeSpectrum()
    #expect(SessionSpectrumRef.fingerprint(of: a) != SessionSpectrumRef.fingerprint(of: b))
    #expect(SessionSpectrumRef.fingerprint(of: a) == SessionSpectrumRef.fingerprint(of: a))
}

@Test func peakMarkLabelRoundTripsThroughSession() throws {
    var mark = PeakMark(spectrumID: UUID(), x: 3086.2, y: 0.67, height: nil, displayMode: "absorbance")
    mark.label = "C-H stretch"
    let file = SessionFile(spectra: [], peaks: [mark], regions: [], viewport: nil,
                           displayMode: "absorbance", autoY: false, selectedID: nil)
    let decoded = try SessionFile.decode(file.encoded())
    #expect(decoded.peaks.first?.label == "C-H stretch")
}

@Test func peakMarkDecodesLegacySessionWithoutLabel() throws {
    // A v1.0.0 session peak has no "label" key; must decode with label == nil.
    let legacy = """
    {"id":"11111111-1111-1111-1111-111111111111",
     "spectrumID":"22222222-2222-2222-2222-222222222222",
     "x":658.0,"y":1.042,"displayMode":"absorbance"}
    """.data(using: .utf8)!
    let mark = try JSONDecoder().decode(PeakMark.self, from: legacy)
    #expect(mark.label == nil)
}

@Test func effectiveLabelPrefersCustomThenFormattedX() {
    var mark = PeakMark(spectrumID: UUID(), x: 3086.2, y: 0.67, height: nil, displayMode: "absorbance")
    #expect(mark.effectiveLabel == "3086.2")
    mark.label = "C-H stretch"
    #expect(mark.effectiveLabel == "C-H stretch")
    mark.label = ""   // cleared in the UI → falls back to the default
    #expect(mark.effectiveLabel == "3086.2")
}
