// Tests/SpectraKitTests/ASDFDecoderTests.swift
import Testing
@testable import SpectraKit

@Test func decodesAFFN() throws {
    let l = try ASDFDecoder.decodeLine("400.0 0.95 0.94 0.93", previousY: nil)
    #expect(l.x == 400.0)
    #expect(l.ys == [0.95, 0.94, 0.93])
    #expect(l.endedInDIF == false)
}

@Test func decodesPAC() throws {
    let l = try ASDFDecoder.decodeLine("400+95+94-93", previousY: nil)
    #expect(l.x == 400)
    #expect(l.ys == [95, 94, -93])
}

@Test func decodesSQZ() throws {
    // @=0 A=1 ... I=9 ; a=-1 ... i=-9
    let l = try ASDFDecoder.decodeLine("400I5H4a2", previousY: nil)
    #expect(l.x == 400)
    #expect(l.ys == [95, 84, -12])
}

@Test func decodesDIFandDUP() throws {
    // J=+1 K=+2 ... R=+9, %=+0, j=-1 ... r=-9 ; T=dup2, U=dup3
    // Start Y=100 (SQZ 'A'+"00"), then DIF +2 (K), DIF -1 (j), then DUP T=2:
    // the last DIF occurs 2 times total, i.e. one extra application of -1.
    let l = try ASDFDecoder.decodeLine("500A00KjT", previousY: nil)
    #expect(l.x == 500)
    #expect(l.ys == [100, 102, 101, 100])
    #expect(l.endedInDIF == true) // DUP of a DIF stays in DIF mode
}

@Test func rejectsGarbage() {
    #expect(throws: ASDFError.self) {
        _ = try ASDFDecoder.decodeLine("not a data line", previousY: nil)
    }
}

@Test func treatsEAsSQZPseudoDigitNotExponent() throws {
    // JCAMP-DX forbids exponential AFFN inside ASDF lines; E is SQZ 5.
    // "100E5" is the value 100 followed by SQZ "E5" = 55.
    let l = try ASDFDecoder.decodeLine("400 100E5", previousY: nil)
    #expect(l.ys == [100, 55])
}

@Test func xOnlyLineYieldsNoYs() throws {
    let l = try ASDFDecoder.decodeLine("400", previousY: nil)
    #expect(l.x == 400)
    #expect(l.ys.isEmpty)
}

@Test func emptyLineThrows() {
    #expect(throws: ASDFError.self) {
        _ = try ASDFDecoder.decodeLine("", previousY: nil)
    }
}

@Test func dupAsFirstYTokenThrows() {
    #expect(throws: ASDFError.self) {
        _ = try ASDFDecoder.decodeLine("400T", previousY: nil)
    }
}

@Test func rejectsImplausiblyLargeDUP() {
    #expect(throws: ASDFError.self) {
        _ = try ASDFDecoder.decodeLine("1 5 s999999999", previousY: nil)
    }
}
