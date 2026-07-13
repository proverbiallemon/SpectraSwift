import Testing
import Foundation
@testable import SpectraKit

private func fixtureURL(_ name: String) throws -> URL {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
        ?? Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
    guard let url else { throw SpectrumFileError.unreadable("fixture \(name) not found") }
    return url
}

@Test func sniffsJCAMPByContent() throws {
    let d = Data("##TITLE=X\n##XUNITS=1/CM\n##YUNITS=ABSORBANCE\n##FIRSTX=1\n##LASTX=2\n##NPOINTS=2\n##XYDATA=(X++(Y..Y))\n1 5 6\n##END=".utf8)
    let spectra = try SpectrumFile.read(data: d, sourceURL: nil)
    #expect(spectra.count == 1)
}

@Test func sniffsOPUSMagicAsUnsupportedForNow() {
    let d = Data([0x0A, 0x0A, 0xFE, 0xFE, 0x00, 0x00])
    #expect(throws: SpectrumFileError.self) {
        _ = try SpectrumFile.read(data: d, sourceURL: nil)
    }
}

@Test func rejectsUnknown() {
    #expect(throws: SpectrumFileError.self) {
        _ = try SpectrumFile.read(data: Data("random".utf8), sourceURL: nil)
    }
}

@Test func readsFromFileURL() throws {
    let url = try fixtureURL("benzene-ir.jdx")
    let spectra = try SpectrumFile.read(url: url)
    #expect(!spectra.isEmpty)
    #expect(spectra[0].sourceURL == url)
}

@Test func unreadableURLThrowsUnreadable() {
    let missing = URL(fileURLWithPath: "/nonexistent/definitely-not-here.jdx")
    do {
        _ = try SpectrumFile.read(url: missing)
        Issue.record("Expected SpectrumFileError.unreadable to be thrown")
    } catch let e as SpectrumFileError {
        guard case .unreadable = e else {
            Issue.record("Expected .unreadable, got \(e)")
            return
        }
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test func emptyAndTinyDataRejected() {
    #expect(throws: SpectrumFileError.self) {
        _ = try SpectrumFile.read(data: Data(), sourceURL: nil)
    }
    #expect(throws: SpectrumFileError.self) {
        _ = try SpectrumFile.read(data: Data([0x0A, 0x0A]), sourceURL: nil)
    }
}
