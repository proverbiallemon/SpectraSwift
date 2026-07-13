import Testing
import Foundation
@testable import SpectraKit

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
