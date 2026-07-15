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

@Test func explicitZeroProminenceKeepsAllExtrema() {
    var pts: [SpectrumPoint] = []
    for i in 0...24 {
        let x = Double(i)
        var y = 0.0
        y = max(y, 10 - 2 * abs(x - 5))
        y = max(y, 6 - 2 * abs(x - 15))
        if i == 20 { y += 0.3 }
        pts.append(SpectrumPoint(x: x, y: y))
    }
    let all = Measure.detectPeaks(in: pts, direction: .maxima, minProminence: 0)
    #expect(all.map(\.x).contains(20))
}

/// The original O(n^2) prominence walk, kept verbatim as the reference
/// oracle for the monotonic-stack rewrite.
private func referenceDetectPeaks(in points: [SpectrumPoint],
                                  direction: PeakDirection,
                                  minProminence: Double?) -> [SpectrumPoint] {
    let pts = points.sorted { $0.x < $1.x }
    guard pts.count >= 3 else { return [] }
    let sign: Double = direction == .maxima ? 1 : -1
    let ys = pts.map { sign * $0.y }
    let yLo = ys.min() ?? 0, yHi = ys.max() ?? 0
    let threshold = minProminence ?? (yHi - yLo) * 0.05
    // Default threshold on a flat spectrum is 0, so there is nothing
    // meaningful to find. An EXPLICIT 0 means "keep every local extremum".
    if minProminence == nil && threshold <= 0 { return [] }
    guard threshold >= 0 else { return [] }

    var result: [SpectrumPoint] = []
    for i in 1..<(pts.count - 1) {
        guard ys[i] > ys[i - 1], ys[i] >= ys[i + 1] else { continue }
        // Walk outward until a higher point (or the end); the prominence
        // is the drop to the higher of the two flanking valley floors.
        var leftMin = ys[i]
        var j = i - 1
        while j >= 0, ys[j] <= ys[i] { leftMin = min(leftMin, ys[j]); j -= 1 }
        var rightMin = ys[i]
        var k = i + 1
        while k < pts.count, ys[k] <= ys[i] { rightMin = min(rightMin, ys[k]); k += 1 }
        let prominence = ys[i] - max(leftMin, rightMin)
        if prominence >= threshold {
            result.append(pts[i])
        }
    }
    return result
}

@Test func monotonicStackMatchesReferenceWalk() {
    var state: UInt64 = 0x9E3779B97F4A7C15
    func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
    for _ in 0..<50 {
        let n = 3 + Int(next() * 300)
        // Quantized ys force plateaus and exact ties, the tricky cases.
        let pts = (0..<n).map { SpectrumPoint(x: Double($0), y: (next() * 10).rounded() / 2) }
        for direction in [PeakDirection.maxima, .minima] {
            for prom in [nil, 0.0, 1.0, 3.0] as [Double?] {
                let got = Measure.detectPeaks(in: pts, direction: direction, minProminence: prom)
                let want = referenceDetectPeaks(in: pts, direction: direction, minProminence: prom)
                #expect(got == want)
            }
        }
    }
}

@Test func detectPeaksHandlesPathologicalShouldersAtScale() {
    // Alternating floor and ever-taller spike: y = i at odd i, 0 at even i.
    // Every odd interior index is a candidate, and in the old O(n^2) walk
    // each candidate's left prominence scan re-crossed every earlier
    // (smaller) spike all the way back to index 0, about 3.6e9 inner
    // iterations at this size (measured quadratic on the reference walk:
    // 0.37s at n=10k, 5.4s at n=40k). The stack version is O(n).
    var pts: [SpectrumPoint] = []
    for i in 0..<120_000 {
        pts.append(SpectrumPoint(x: Double(i), y: i % 2 == 1 ? Double(i) : 0))
    }
    let peaks = Measure.detectPeaks(in: pts, direction: .maxima, minProminence: nil)
    // Both valley floors of each spike are 0, so its prominence is its own
    // height i. Default threshold is 5% of the y-range: 0.05 * 119999 =
    // 5999.95. Candidates are the odd i in 1...119997 (endpoints excluded);
    // those with i >= 6001 pass: (119997 - 6001) / 2 + 1 = 56999. The same
    // formula was verified against the reference walk at n=10k (4749) and
    // n=40k (18999).
    #expect(peaks.count == 56999)
    #expect(peaks.first?.x == 6001)
    #expect(peaks.last?.x == 119_997)
}
