import Foundation

public enum SmoothError: Error, Equatable {
    case invalidParameters(String)
    case tooFewPoints(needed: Int, have: Int)
    case stickData
}

public enum Smooth {
    /// Savitzky-Golay smoothing. Returns a new derived spectrum; the input
    /// is untouched. Assumes an even x grid (warns if it is not).
    public static func savitzkyGolay(_ s: Spectrum, window: Int, polyOrder: Int) throws -> Spectrum {
        guard window % 2 == 1, (5...25).contains(window) else {
            throw SmoothError.invalidParameters("window must be odd, between 5 and 25")
        }
        guard (2...3).contains(polyOrder) else {
            throw SmoothError.invalidParameters("polynomial order must be 2 or 3")
        }
        guard s.dataForm == .continuous else { throw SmoothError.stickData }
        guard s.points.count >= window else {
            throw SmoothError.tooFewPoints(needed: window, have: s.points.count)
        }
        let pts = s.points.sorted { $0.x < $1.x }
        guard let weights = coefficients(window: window, polyOrder: polyOrder) else {
            throw SmoothError.invalidParameters("could not derive filter coefficients")
        }
        let half = window / 2
        let n = pts.count
        var out = pts
        for i in 0..<n {
            var acc = 0.0
            for k in -half...half {
                var idx = i + k                     // mirror padding at both edges
                if idx < 0 { idx = -idx }
                if idx >= n { idx = 2 * n - 2 - idx }
                acc += weights[k + half] * pts[idx].y
            }
            out[i].y = acc
        }
        var warnings: [SpectrumWarning] = []
        if n >= 3 {
            let d0 = pts[1].x - pts[0].x
            let uneven = d0 != 0 && (2..<n).contains {
                abs((pts[$0].x - pts[$0 - 1].x) - d0) > abs(d0) * 0.005
            }
            if uneven {
                warnings.append(SpectrumWarning(
                    "X spacing is not uniform; Savitzky-Golay assumes an even grid, so smoothed values are approximate."))
            }
        }
        return Spectrum(
            title: "\(s.title) (smoothed)",
            origin: s.origin, owner: s.owner, sourceURL: nil,
            xUnit: s.xUnit, yUnit: s.yUnit, dataForm: .continuous,
            points: out,
            parameters: [Parameter(key: "SMOOTHING",
                                   value: "Savitzky-Golay, window \(window), order \(polyOrder)")],
            warnings: warnings)
    }

    /// Central convolution weights for a symmetric window: solve the
    /// least-squares normal equations (A'A)g = e0 over offsets z in
    /// -half...half, then w_i = sum_j g_j * z_i^j.
    static func coefficients(window: Int, polyOrder p: Int) -> [Double]? {
        let half = window / 2
        var normal = [[Double]](repeating: .init(repeating: 0, count: p + 1), count: p + 1)
        for z in -half...half {
            var pow = [Double](repeating: 1, count: 2 * p + 1)
            for i in 1...(2 * p) { pow[i] = pow[i - 1] * Double(z) }
            for j in 0...p { for k in 0...p { normal[j][k] += pow[j + k] } }
        }
        var e0 = [Double](repeating: 0, count: p + 1); e0[0] = 1
        guard let g = solveLinear(normal, e0) else { return nil }
        return (-half...half).map { z in
            var acc = 0.0, zp = 1.0
            for j in 0...p { acc += g[j] * zp; zp *= Double(z) }
            return acc
        }
    }

    /// Gaussian elimination with partial pivoting for the tiny (<=4x4) system.
    private static func solveLinear(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix, b = rhs
        let n = b.count
        for col in 0..<n {
            var pivot = col
            for r in (col + 1)..<n where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            if abs(a[pivot][col]) < 1e-12 { return nil }
            a.swapAt(col, pivot); b.swapAt(col, pivot)
            for r in (col + 1)..<n {
                let f = a[r][col] / a[col][col]
                for c in col..<n { a[r][c] -= f * a[col][c] }
                b[r] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = b[r]
            for c in (r + 1)..<n { s -= a[r][c] * x[c] }
            x[r] = s / a[r][r]
        }
        return x
    }
}
