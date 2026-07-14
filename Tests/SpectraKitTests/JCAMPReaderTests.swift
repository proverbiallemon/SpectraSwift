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
    // YFACTOR scaling is floating-point; compare with tolerance.
    #expect(s.points[0].x == 400)
    #expect(abs(s.points[0].y - 0.95) < 1e-12)
    #expect(s.points[4].x == 404)
    #expect(abs(s.points[4].y - 0.91) < 1e-12)
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

@Test func warnsOnMissingDIFCheckpoint() throws {
    let text = """
    ##TITLE=TRUNCATED DIF
    ##JCAMP-DX=4.24
    ##XUNITS=1/CM
    ##YUNITS=TRANSMITTANCE
    ##XFACTOR=1.0
    ##YFACTOR=1.0
    ##FIRSTX=100
    ##LASTX=104
    ##NPOINTS=5
    ##XYDATA=(X++(Y..Y))
    100A00KKK
    104
    ##END=
    """
    let s = try JCAMPReader.read(data: Data(text.utf8), sourceURL: nil)[0]
    #expect(s.points.count == 4)
    #expect(s.warnings.contains { $0.message.contains("Missing DIF checkpoint") })
}

@Test func warnsWhenXSpacingUnknown() throws {
    let text = """
    ##TITLE=NO HEADERS
    ##JCAMP-DX=4.24
    ##XUNITS=1/CM
    ##YUNITS=TRANSMITTANCE
    ##XYDATA=(X++(Y..Y))
    400 950 940 930
    ##END=
    """
    let s = try JCAMPReader.read(data: Data(text.utf8), sourceURL: nil)[0]
    #expect(s.warnings.contains { $0.message.contains("Cannot determine x spacing") })
}

@Test func usesLineAbscissaWhenFIRSTXAbsent() throws {
    let text = """
    ##TITLE=NO FIRSTX
    ##JCAMP-DX=4.24
    ##XUNITS=1/CM
    ##YUNITS=ABSORBANCE
    ##XFACTOR=1.0
    ##YFACTOR=1.0
    ##DELTAX=4.0
    ##XYDATA=(X++(Y..Y))
    450 1 2 3
    462 4 5 6
    ##END=
    """
    let s = try JCAMPReader.read(data: Data(text.utf8), sourceURL: nil)[0]
    #expect(s.points.map(\.x) == [450, 454, 458, 462, 466, 470])
}

@Test func warnsOnDIFCheckpointMismatch() throws {
    let text = """
    ##TITLE=BAD CHECKPOINT
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
    104A99%%
    ##END=
    """
    let s = try JCAMPReader.read(data: Data(text.utf8), sourceURL: nil)[0]
    #expect(s.warnings.contains { $0.message.contains("DIF checkpoint mismatch") })
}

@Test func parsesDescendingXFile() throws {
    let text = """
    ##TITLE=DESCENDING
    ##JCAMP-DX=4.24
    ##XUNITS=1/CM
    ##YUNITS=ABSORBANCE
    ##XFACTOR=1.0
    ##YFACTOR=1.0
    ##FIRSTX=4000
    ##LASTX=3996
    ##NPOINTS=5
    ##XYDATA=(X++(Y..Y))
    4000 1 2 3
    3997 4 5
    ##END=
    """
    let s = try JCAMPReader.read(data: Data(text.utf8), sourceURL: nil)[0]
    #expect(s.points.map(\.x) == [4000, 3999, 3998, 3997, 3996])
}
