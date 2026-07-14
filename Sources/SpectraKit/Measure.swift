import Foundation

public enum PeakDirection: String, Sendable, Codable {
    case maxima, minima
}

public enum MeasureError: Error, Equatable {
    case noOverlap
    case emptyRegion
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
        guard threshold > 0 else { return [] }

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
}
