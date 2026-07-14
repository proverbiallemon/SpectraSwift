import Testing
@testable import SpectraKit

/// Symmetric triangle peak centered at x=5, apex y=10, on a y=0 base.
private let triangle: [SpectrumPoint] = (0...10).map {
    SpectrumPoint(x: Double($0), y: 10 - 2 * abs(Double($0) - 5))
}

@Test func nearestPeakClimbsToApex() {
    let p = Measure.nearestPeak(in: triangle, nearX: 3.2, direction: .maxima)
    #expect(p == SpectrumPoint(x: 5, y: 10))
}

@Test func nearestPeakFindsMinima() {
    let dip = triangle.map { SpectrumPoint(x: $0.x, y: -$0.y) }
    let p = Measure.nearestPeak(in: dip, nearX: 6.7, direction: .minima)
    #expect(p == SpectrumPoint(x: 5, y: -10))
}

@Test func nearestPeakHandlesUnsortedInput() {
    let p = Measure.nearestPeak(in: triangle.reversed(), nearX: 4.0, direction: .maxima)
    #expect(p == SpectrumPoint(x: 5, y: 10))
}

@Test func nearestPeakNilOnTinyInput() {
    #expect(Measure.nearestPeak(in: [SpectrumPoint(x: 1, y: 1)], nearX: 1, direction: .maxima) == nil)
}

@Test func detectPeaksFindsBothPeaksNotNoise() {
    // Two clear peaks (y=10 at x=5, y=6 at x=15) and a tiny bump (y=0.3 at x=20)
    var pts: [SpectrumPoint] = []
    for i in 0...24 {
        let x = Double(i)
        var y = 0.0
        y = max(y, 10 - 2 * abs(x - 5))
        y = max(y, 6 - 2 * abs(x - 15))
        if i == 20 { y += 0.3 }
        pts.append(SpectrumPoint(x: x, y: y))
    }
    let peaks = Measure.detectPeaks(in: pts, direction: .maxima, minProminence: nil)
    #expect(peaks.map(\.x) == [5, 15])
}

@Test func detectPeaksRespectsExplicitProminence() {
    var pts: [SpectrumPoint] = []
    for i in 0...24 {
        let x = Double(i)
        var y = 0.0
        y = max(y, 10 - 2 * abs(x - 5))
        y = max(y, 6 - 2 * abs(x - 15))
        pts.append(SpectrumPoint(x: x, y: y))
    }
    let strict = Measure.detectPeaks(in: pts, direction: .maxima, minProminence: 8)
    #expect(strict.map(\.x) == [5])
}

@Test func detectPeaksIgnoresEndpoints() {
    // Monotonic ramp: highest point is the endpoint — not a peak.
    let ramp = (0...10).map { SpectrumPoint(x: Double($0), y: Double($0)) }
    #expect(Measure.detectPeaks(in: ramp, direction: .maxima, minProminence: nil).isEmpty)
}

@Test func detectPeaksFindsMinimaForTransmittance() {
    // Transmittance-style: flat 1.0 with a dip to 0.2 at x=5
    var pts: [SpectrumPoint] = []
    for i in 0...10 {
        let x = Double(i)
        let y: Double
        if i == 5 {
            y = 0.2
        } else if i == 4 || i == 6 {
            y = 0.6
        } else {
            y = 1.0
        }
        pts.append(SpectrumPoint(x: x, y: y))
    }
    let peaks = Measure.detectPeaks(in: pts, direction: .minima, minProminence: nil)
    #expect(peaks.map { $0.x } == [5])
}
