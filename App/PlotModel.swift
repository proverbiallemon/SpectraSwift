// App/PlotModel.swift
import SwiftUI
import SpectraKit

struct PlotViewport: Equatable {
    var xLo: Double, xHi: Double, yLo: Double, yHi: Double

    static func fitting(_ pointSets: [[SpectrumPoint]]) -> PlotViewport? {
        let all = pointSets.flatMap { $0 }
        guard let xlo = all.map(\.x).min(), let xhi = all.map(\.x).max(),
              let ylo = all.map(\.y).min(), let yhi = all.map(\.y).max() else { return nil }
        let xPad = (xhi - xlo) * 0.02, yPad = (yhi - ylo) * 0.05
        return PlotViewport(xLo: xlo - max(xPad, 1e-12), xHi: xhi + max(xPad, 1e-12),
                            yLo: ylo - yPad, yHi: yhi + max(yPad, 1e-12))
    }

    func zoomed(by factor: Double, aboutX fx: Double, aboutY fy: Double) -> PlotViewport {
        // fx/fy are 0-1 fractions of the viewport the zoom centers on
        let cx = xLo + (xHi - xLo) * fx
        let cy = yLo + (yHi - yLo) * fy
        return PlotViewport(
            xLo: cx - (cx - xLo) / factor, xHi: cx + (xHi - cx) / factor,
            yLo: cy - (cy - yLo) / factor, yHi: cy + (yHi - cy) / factor)
    }

    func panned(fractionX dx: Double, fractionY dy: Double) -> PlotViewport {
        let w = xHi - xLo, h = yHi - yLo
        return PlotViewport(xLo: xLo + w * dx, xHi: xHi + w * dx,
                            yLo: yLo + h * dy, yHi: yHi + h * dy)
    }
}

/// Maps data coordinates to view points and back. Owns the reversed-X
/// convention so nothing else has to think about it.
struct PlotTransform {
    let viewport: PlotViewport
    let size: CGSize
    let inset: EdgeInsets   // room for axis labels
    let xReversed: Bool

    var plotRect: CGRect {
        CGRect(x: inset.leading, y: inset.top,
               width: max(1, size.width - inset.leading - inset.trailing),
               height: max(1, size.height - inset.top - inset.bottom))
    }

    func point(_ p: SpectrumPoint) -> CGPoint {
        let fx = (p.x - viewport.xLo) / (viewport.xHi - viewport.xLo)
        let fy = (p.y - viewport.yLo) / (viewport.yHi - viewport.yLo)
        let px = xReversed ? 1 - fx : fx
        return CGPoint(x: plotRect.minX + plotRect.width * px,
                       y: plotRect.maxY - plotRect.height * fy)  // y up
    }

    func dataXY(at v: CGPoint) -> (x: Double, y: Double) {
        var fx = (v.x - plotRect.minX) / plotRect.width
        if xReversed { fx = 1 - fx }
        let fy = (plotRect.maxY - v.y) / plotRect.height
        return (viewport.xLo + (viewport.xHi - viewport.xLo) * fx,
                viewport.yLo + (viewport.yHi - viewport.yLo) * fy)
    }
}

enum IRDisplayMode: String, CaseIterable {
    case native = "As Recorded"
    case transmittance = "Transmittance"
    case absorbance = "Absorbance"
}

@MainActor @Observable
final class PlotModel {
    /// nil means auto-fit to visible spectra.
    var viewport: PlotViewport?
    var displayMode: IRDisplayMode = .native
    var crosshair: CGPoint?   // view coords, set by hover in Task 9

    /// Points after T↔A conversion and (if mixed y-units) 0-1 normalization.
    func effectivePoints(for s: Spectrum, normalize: Bool) -> [SpectrumPoint] {
        var pts = s.points
        switch (displayMode, s.yUnit) {
        case (.absorbance, .transmittance):
            pts = pts.compactMap { p in
                p.y > 0 ? SpectrumPoint(x: p.x, y: -log10(p.y)) : nil
            }
        case (.transmittance, .absorbance):
            pts = pts.map { SpectrumPoint(x: $0.x, y: pow(10, -$0.y)) }
        default:
            break
        }
        if normalize, let lo = pts.map(\.y).min(), let hi = pts.map(\.y).max(), hi > lo {
            pts = pts.map { SpectrumPoint(x: $0.x, y: ($0.y - lo) / (hi - lo)) }
        }
        return pts
    }

    /// Y unit actually being displayed for a spectrum under the current mode.
    func effectiveYUnit(for s: Spectrum) -> YUnit {
        switch (displayMode, s.yUnit) {
        case (.absorbance, .transmittance): .absorbance
        case (.transmittance, .absorbance): .transmittance
        default: s.yUnit
        }
    }

    private var cachedSets: [UUID: [SpectrumPoint]] = [:]
    private var cacheKey: String = ""

    /// Cached effectivePoints, invalidated when displayMode/normalize or the
    /// visible spectrum set changes.
    func pointSets(for items: [LoadedSpectrum], normalize: Bool) -> [[SpectrumPoint]] {
        let key = "\(displayMode.rawValue)|\(normalize)|" + items.map { $0.id.uuidString }.joined(separator: ",")
        if key != cacheKey {
            cacheKey = key
            cachedSets = [:]
            for item in items {
                cachedSets[item.id] = effectivePoints(for: item.spectrum, normalize: normalize)
            }
        }
        return items.compactMap { cachedSets[$0.id] }
    }
}

/// "Nice number" axis ticks (1/2/5 × 10ⁿ steps).
func niceTicks(lo: Double, hi: Double, target: Int = 6) -> [Double] {
    guard hi > lo, target > 1 else { return [] }
    let rawStep = (hi - lo) / Double(target)
    let mag = pow(10, floor(log10(rawStep)))
    let norm = rawStep / mag
    let step = (norm < 1.5 ? 1.0 : norm < 3 ? 2.0 : norm < 7 ? 5.0 : 10.0) * mag
    var t = (lo / step).rounded(.up) * step
    var out: [Double] = []
    while t <= hi + step * 1e-9 {
        out.append(t.magnitude < step * 1e-9 ? 0 : t)
        t += step
    }
    return out
}
