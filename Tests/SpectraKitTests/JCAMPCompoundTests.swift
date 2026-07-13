import Testing
import Foundation
@testable import SpectraKit

@Test func parsesCompoundBlocks() throws {
    let compound = """
    ##TITLE=LINK FILE
    ##JCAMP-DX=4.24
    ##DATA TYPE=LINK
    ##BLOCKS=2
    ##TITLE=CHILD ONE
    ##JCAMP-DX=4.24
    ##XUNITS=1/CM
    ##YUNITS=ABSORBANCE
    ##XFACTOR=1
    ##YFACTOR=1
    ##FIRSTX=100
    ##LASTX=102
    ##NPOINTS=3
    ##XYDATA=(X++(Y..Y))
    100 1 2 3
    ##END=
    ##TITLE=CHILD TWO
    ##JCAMP-DX=4.24
    ##XUNITS=1/CM
    ##YUNITS=ABSORBANCE
    ##XFACTOR=1
    ##YFACTOR=1
    ##FIRSTX=200
    ##LASTX=202
    ##NPOINTS=3
    ##XYDATA=(X++(Y..Y))
    200 4 5 6
    ##END=
    ##END=
    """
    let spectra = try JCAMPReader.read(data: Data(compound.utf8), sourceURL: nil)
    #expect(spectra.count == 2)
    #expect(spectra[0].title == "CHILD ONE")
    #expect(spectra[1].title == "CHILD TWO")
    #expect(spectra[1].points.first?.x == 200)
}

@Test func parsesNTUPLES() throws {
    let ntuples = """
    ##TITLE=NTUPLE TEST
    ##JCAMP-DX=5.00
    ##DATA TYPE=MASS SPECTRUM
    ##NTUPLES=MASS SPECTRUM
    ##VAR_NAME=MASS, INTENSITY
    ##SYMBOL=X, Y
    ##VAR_TYPE=INDEPENDENT, DEPENDENT
    ##VAR_FORM=AFFN, AFFN
    ##UNITS=M/Z, RELATIVE ABUNDANCE
    ##FIRST=15, 210
    ##LAST=91, 9999
    ##PAGE=1
    ##DATA TABLE=(XY..XY), PEAKS
    15,210 27,990 39,1220
    91,9999
    ##END NTUPLES=MASS SPECTRUM
    ##END=
    """
    let spectra = try JCAMPReader.read(data: Data(ntuples.utf8), sourceURL: nil)
    #expect(spectra.count == 1)
    let s = spectra[0]
    #expect(s.dataForm == .peaks)
    #expect(s.xUnit == .massCharge)
    #expect(s.points.count == 4)
    #expect(s.points.last == SpectrumPoint(x: 91, y: 9999))
}
