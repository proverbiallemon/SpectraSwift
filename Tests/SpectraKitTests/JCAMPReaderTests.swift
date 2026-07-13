import Testing
import Foundation
@testable import SpectraKit

private func jcamp(_ body: String) -> Data { Data(body.utf8) }

let simpleIR = """
##TITLE=TEST IR
##JCAMP-DX=4.24
##DATA TYPE=INFRARED SPECTRUM
##ORIGIN=TEST
##OWNER=PUBLIC
##XUNITS=1/CM
##YUNITS=TRANSMITTANCE
##XFACTOR=1.0
##YFACTOR=0.001
##FIRSTX=400
##LASTX=404
##NPOINTS=5
##XYDATA=(X++(Y..Y))
400 950 940 930
403 920 910
##END=
"""

@Test func parsesSimpleXYDATA() throws {
    let spectra = try JCAMPReader.read(data: jcamp(simpleIR), sourceURL: nil)
    #expect(spectra.count == 1)
    let s = spectra[0]
    #expect(s.title == "TEST IR")
    #expect(s.xUnit == .wavenumber)
    #expect(s.yUnit == .transmittance)
    #expect(s.dataForm == .continuous)
    #expect(s.points.count == 5)
    #expect(s.points[0] == SpectrumPoint(x: 400, y: 0.95))
    #expect(s.points[4] == SpectrumPoint(x: 404, y: 0.91))
    #expect(s.warnings.isEmpty)
}

@Test func parsesDIFWithCheckpoint() throws {
    // DIF lines: next line's first Y is a checkpoint that must equal the
    // running Y and is NOT a new data point.
    let text = """
    ##TITLE=DIF TEST
    ##JCAMP-DX=4.24
    ##XUNITS=1/CM
    ##YUNITS=TRANSMITTANCE
    ##XFACTOR=1.0
    ##YFACTOR=1.0
    ##FIRSTX=100
    ##LASTX=105
    ##NPOINTS=6
    ##XYDATA=(X++(Y..Y))
    100A00KKK
    104A06%%
    ##END=
    """
    // Line 1: Y=100, then DIF +2,+2,+2 → 100,102,104,106 (x=100..103)
    // Line 2: A06 is the checkpoint (must equal running Y=106; consumed, not a
    // datum), then two DIF +0 values → 106 at x=104 and 106 at x=105.
    let s = try JCAMPReader.read(data: jcamp(text), sourceURL: nil)[0]
    #expect(s.points.map(\.y) == [100, 102, 104, 106, 106, 106])
    #expect(s.warnings.isEmpty)
}

@Test func warnsOnNPointsMismatch() throws {
    let bad = simpleIR.replacingOccurrences(of: "##NPOINTS=5", with: "##NPOINTS=7")
    let s = try JCAMPReader.read(data: jcamp(bad), sourceURL: nil)[0]
    #expect(s.points.count == 5)
    #expect(!s.warnings.isEmpty)
}

@Test func toleratesCRLFAndComments() throws {
    let crlf = simpleIR
        .replacingOccurrences(of: "\n", with: "\r\n")
        .replacingOccurrences(of: "##ORIGIN=TEST", with: "##ORIGIN=TEST $$ inline comment")
    let s = try JCAMPReader.read(data: jcamp(crlf), sourceURL: nil)[0]
    #expect(s.points.count == 5)
    #expect(s.origin == "TEST")
}

@Test func rejectsNonJCAMP() {
    #expect(throws: JCAMPError.self) {
        _ = try JCAMPReader.read(data: jcamp("hello world"), sourceURL: nil)
    }
}
