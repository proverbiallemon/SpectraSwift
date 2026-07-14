import Foundation

public enum PeakDirection: String, Sendable, Codable {
    case maxima, minima
}

public enum MeasureError: Error, Equatable {
    case noOverlap
    case emptyRegion
    case unitMismatch
}

/// Measurement math over spectrum point arrays. Functions sort input by x
/// internally — callers may pass descending or unordered data.
public enum Measure {

    /// Hill-climb from the sample nearest `nearX` to the local extremum.
    public static func nearestPeak(in points: [SpectrumPoint], nearX: Double,
                                   direction: PeakDirection) -> SpectrumPoint? {
        let pts = points.sorted { $0.x < $1.x }
        guard pts.count >= 3 else { return nil }
        let sign: Double = direction == .maxima ? 1 : -1
        guard var i = nearestIndex(in: pts, to: nearX) else { return nil }
        while true {
            let here = sign * pts[i].y
            let left = i > 0 ? sign * pts[i - 1].y : -.infinity
            let right = i < pts.count - 1 ? sign * pts[i + 1].y : -.infinity
            if left > here && left >= right { i -= 1 }
            else if right > here { i += 1 }
            else { break }
        }
        // An extremum at the array edge is a truncated feature, not a peak.
        guard i > 0, i < pts.count - 1 else { return nil }
        return pts[i]
    }

    /// Prominence-based local-extrema detection. `minProminence` nil →
    /// 5% of the data's y-range. Endpoints are never peaks.
    public static func detectPeaks(in points: [SpectrumPoint],
                                   direction: PeakDirection,
                                   minProminence: Double?) -> [SpectrumPoint] {
        let pts = points.sorted { $0.x < $1.x }
        guard pts.count >= 3 else { return [] }
        let sign: Double = direction == .maxima ? 1 : -1
        let ys = pts.map { sign * $0.y }
        let yLo = ys.min() ?? 0, yHi = ys.max() ?? 0
        let threshold = minProminence ?? (yHi - yLo) * 0.05
        // Default threshold on a flat spectrum is 0 — nothing meaningful to
        // find. An EXPLICIT 0 means "keep every local extremum".
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

    static func nearestIndex(in sorted: [SpectrumPoint], to x: Double) -> Int? {
        guard !sorted.isEmpty else { return nil }
        var best = 0
        var bestDist = abs(sorted[0].x - x)
        for (i, p) in sorted.enumerated() where abs(p.x - x) < bestDist {
            best = i; bestDist = abs(p.x - x)
        }
        return best
    }

    /// Binary-search interpolation over an array KNOWN to be x-ascending.
    static func interpolatedYSorted(_ pts: [SpectrumPoint], at x: Double) -> Double? {
        guard let first = pts.first, let last = pts.last,
              x >= first.x, x <= last.x else { return nil }
        var lo = 0, hi = pts.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if pts[mid].x <= x { lo = mid } else { hi = mid }
        }
        if pts[lo].x == x { return pts[lo].y }
        let a = pts[lo], b = pts[hi]
        guard b.x > a.x else { return a.y }
        let t = (x - a.x) / (b.x - a.x)
        return a.y + t * (b.y - a.y)
    }

    public static func interpolatedY(in points: [SpectrumPoint], at x: Double) -> Double? {
        interpolatedYSorted(points.sorted { $0.x < $1.x }, at: x)
    }

    /// Peak apex height above the straight line joining the curve at x1/x2.
    /// Negative when the apex sits below the chord (e.g. a transmittance
    /// dip measured as maxima) — callers decide how to present sign.
    public static func chordBaselineHeight(points: [SpectrumPoint], peakX: Double,
                                           x1: Double, x2: Double) -> Double? {
        let pts = points.sorted { $0.x < $1.x }
        guard x1 != x2,
              let apexY = interpolatedYSorted(pts, at: peakX),
              let y1 = interpolatedYSorted(pts, at: min(x1, x2)),
              let y2 = interpolatedYSorted(pts, at: max(x1, x2)) else { return nil }
        let lo = min(x1, x2), hi = max(x1, x2)
        let chordY = y1 + (peakX - lo) / (hi - lo) * (y2 - y1)
        return apexY - chordY
    }

    /// Signed trapezoidal area between the curve and the chord joining the
    /// curve values at the (clamped, interpolated) endpoints.
    public static func integrate(points: [SpectrumPoint], from: Double,
                                 to: Double) throws -> Double {
        let lo = min(from, to), hi = max(from, to)
        let pts = points.sorted { $0.x < $1.x }
        guard lo != hi,
              let yLo = interpolatedYSorted(pts, at: lo),
              let yHi = interpolatedYSorted(pts, at: hi) else {
            throw MeasureError.emptyRegion
        }
        var xs: [SpectrumPoint] = [SpectrumPoint(x: lo, y: yLo)]
        xs += pts.filter { $0.x > lo && $0.x < hi }
        xs.append(SpectrumPoint(x: hi, y: yHi))
        var curveArea = 0.0
        for i in 1..<xs.count {
            curveArea += (xs[i].x - xs[i - 1].x) * (xs[i].y + xs[i - 1].y) / 2
        }
        let chordArea = (hi - lo) * (yLo + yHi) / 2
        return curveArea - chordArea
    }

    /// A − B: b linearly interpolated onto a's grid over the overlapping
    /// x-range. Result inherits a's units and form.
    public static func subtract(_ a: Spectrum, minus b: Spectrum) throws -> Spectrum {
        let a = a.convertedToWavenumber() ?? a
        let b = b.convertedToWavenumber() ?? b
        guard a.xUnit == b.xUnit else {
            throw MeasureError.unitMismatch
        }
        let aPts = a.points.sorted { $0.x < $1.x }
        let bPts = b.points.sorted { $0.x < $1.x }
        guard let aLo = aPts.first?.x, let aHi = aPts.last?.x,
              let bLo = bPts.first?.x, let bHi = bPts.last?.x,
              max(aLo, bLo) < min(aHi, bHi) else {
            throw MeasureError.noOverlap
        }
        let lo = max(aLo, bLo), hi = min(aHi, bHi)
        var pts: [SpectrumPoint] = []
        for p in aPts where p.x >= lo && p.x <= hi {
            if let by = interpolatedYSorted(bPts, at: p.x) {
                pts.append(SpectrumPoint(x: p.x, y: p.y - by))
            }
        }
        var warnings: [SpectrumWarning] = []
        if lo > aLo || hi < aHi {
            warnings.append(SpectrumWarning(
                "Subtraction limited to the overlap \(String(format: "%.6g", lo))–\(String(format: "%.6g", hi)); points outside it were dropped"))
        }
        if a.yUnit != b.yUnit {
            warnings.append(SpectrumWarning(
                "Subtracted spectra have different y-units (\(a.yUnit.label) − \(b.yUnit.label))"))
        }
        return Spectrum(
            title: "\(a.title) − \(b.title)",
            origin: a.origin, owner: a.owner, sourceURL: nil,
            xUnit: a.xUnit, yUnit: a.yUnit, dataForm: a.dataForm,
            points: pts, parameters: [], warnings: warnings)
    }
}
