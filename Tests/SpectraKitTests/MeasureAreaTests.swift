import Testing
@testable import SpectraKit

private let triangle: [SpectrumPoint] = (0...10).map {
    SpectrumPoint(x: Double($0), y: 10 - 2 * abs(Double($0) - 5))
}

@Test func integratesTriangleAboveChord() throws {
    // Full triangle on a zero chord: area = 1/2 * base * height = 1/2*10*10 = 50
    let area = try Measure.integrate(points: triangle, from: 0, to: 10)
    #expect(abs(area - 50) < 1e-9)
}

@Test func integrationSubtractsChord() throws {
    // Offset the whole triangle by +3: chord endpoints are both y=3, so the
    // chord contribution cancels and the area is still 50.
    let lifted = triangle.map { SpectrumPoint(x: $0.x, y: $0.y + 3) }
    let area = try Measure.integrate(points: lifted, from: 0, to: 10)
    #expect(abs(area - 50) < 1e-9)
}

@Test func integrationInterpolatesEndpoints() throws {
    // Integrate half the triangle: from 5 to 10 the curve falls 10→0
    // linearly; chord from (5,10) to (10,0) IS the curve → area 0.
    let area = try Measure.integrate(points: triangle, from: 5, to: 10)
    #expect(abs(area) < 1e-9)
}

@Test func integrationOrdersItsBounds() throws {
    let a = try Measure.integrate(points: triangle, from: 10, to: 0)
    #expect(abs(a - 50) < 1e-9)
}

@Test func integrationRejectsEmptyRegion() {
    #expect(throws: MeasureError.emptyRegion) {
        _ = try Measure.integrate(points: triangle, from: 4.2, to: 4.2)
    }
    #expect(throws: MeasureError.emptyRegion) {
        _ = try Measure.integrate(points: triangle, from: 40, to: 50)
    }
}

@Test func chordBaselineHeightMeasuresAboveChord() {
    // Lifted triangle: apex y=13, chord over [0,10] sits at y=3 → height 10.
    let lifted = triangle.map { SpectrumPoint(x: $0.x, y: $0.y + 3) }
    let h = Measure.chordBaselineHeight(points: lifted, peakX: 5, x1: 0, x2: 10)
    #expect(h != nil && abs(h! - 10) < 1e-9)
}

@Test func chordBaselineHeightNilOutsideData() {
    #expect(Measure.chordBaselineHeight(points: triangle, peakX: 50, x1: 0, x2: 10) == nil)
}

@Test func interpolatedYMatchesLinearScanOnRandomishGrid() {
    let pts = [(0.0, 1.0), (1.5, 3.0), (2.0, 2.0), (7.0, 9.0), (11.0, 0.0)]
        .map { SpectrumPoint(x: $0.0, y: $0.1) }
    for x in stride(from: 0.0, through: 11.0, by: 0.25) {
        let expected: Double = {
            if let exact = pts.first(where: { $0.x == x }) { return exact.y }
            let hi = pts.firstIndex(where: { $0.x > x })!
            let a = pts[hi - 1], b = pts[hi]
            return a.y + (x - a.x) / (b.x - a.x) * (b.y - a.y)
        }()
        let got = Measure.interpolatedY(in: pts, at: x)
        #expect(got != nil && abs(got! - expected) < 1e-12, "x=\(x)")
    }
}
