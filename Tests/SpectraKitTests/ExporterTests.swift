import Testing
import Foundation
@testable import SpectraKit

private let sample = Spectrum(
    title: "S", origin: "O", owner: "W", sourceURL: nil,
    xUnit: .wavenumber, yUnit: .absorbance, dataForm: .continuous,
    points: [SpectrumPoint(x: 400, y: 0.5), SpectrumPoint(x: 401, y: 0.25)],
    parameters: [], warnings: [])

@Test func exportsCSV() {
    let csv = CSVExporter.export(sample)
    let lines = csv.split(separator: "\n")
    #expect(lines[0] == "Wavenumber (cm⁻¹),Absorbance")
    #expect(lines[1] == "400,0.5")
    #expect(lines.count == 3)
}

@Test func exportsJCAMPRoundTrip() throws {
    let text = JCAMPExporter.export(sample)
    #expect(text.hasPrefix("##TITLE=S"))
    let back = try JCAMPReader.read(data: Data(text.utf8), sourceURL: nil)[0]
    #expect(back.points == sample.points)
    #expect(back.yUnit == .absorbance)
}
