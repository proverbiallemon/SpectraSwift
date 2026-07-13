// App/PlotView.swift
import SwiftUI
import SpectraKit

struct PlotView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlotModel.self) private var plot

    private let inset = EdgeInsets(top: 12, leading: 56, bottom: 36, trailing: 16)

    /// Mixed y-units among visible spectra → normalize each trace 0-1.
    private var mustNormalize: Bool {
        let units = Set(appState.visibleSpectra.map {
            plot.effectiveYUnit(for: $0.spectrum).label
        })
        return units.count > 1
    }

    /// X axis reversed when every visible spectrum uses a reversed unit.
    private var xReversed: Bool {
        let vs = appState.visibleSpectra
        return !vs.isEmpty && vs.allSatisfy(\.spectrum.xUnit.isConventionallyReversed)
    }

    var body: some View {
        Canvas { ctx, size in
            let visible = appState.visibleSpectra
            let normalize = mustNormalize
            let sets = visible.map {
                plot.effectivePoints(for: $0.spectrum, normalize: normalize)
            }
            guard let vp = plot.viewport ?? PlotViewport.fitting(sets) else { return }
            let t = PlotTransform(viewport: vp, size: size,
                                  inset: inset, xReversed: xReversed)

            drawAxes(ctx, t, normalize: normalize, visible: visible)
            ctx.clip(to: Path(t.plotRect))
            for (item, pts) in zip(visible, sets) {
                draw(pts, form: item.spectrum.dataForm,
                     color: item.color, in: ctx, transform: t)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topTrailing) { legend }
    }

    private func draw(_ pts: [SpectrumPoint], form: DataForm, color: Color,
                      in ctx: GraphicsContext, transform t: PlotTransform) {
        guard !pts.isEmpty else { return }
        switch form {
        case .continuous:
            var path = Path()
            path.move(to: t.point(pts[0]))
            for p in pts.dropFirst() { path.addLine(to: t.point(p)) }
            ctx.stroke(path, with: .color(color), lineWidth: 1.2)
        case .peaks:
            let baseline = t.point(SpectrumPoint(x: 0, y: max(0, t.viewport.yLo))).y
            var path = Path()
            for p in pts {
                let top = t.point(p)
                path.move(to: CGPoint(x: top.x, y: min(baseline, t.plotRect.maxY)))
                path.addLine(to: top)
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }

    private func drawAxes(_ ctx: GraphicsContext, _ t: PlotTransform,
                          normalize: Bool, visible: [LoadedSpectrum]) {
        let r = t.plotRect
        ctx.stroke(Path(r), with: .color(.secondary.opacity(0.6)), lineWidth: 1)

        for x in niceTicks(lo: t.viewport.xLo, hi: t.viewport.xHi) {
            let vx = t.point(SpectrumPoint(x: x, y: t.viewport.yLo)).x
            var grid = Path()
            grid.move(to: CGPoint(x: vx, y: r.minY))
            grid.addLine(to: CGPoint(x: vx, y: r.maxY))
            ctx.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            ctx.draw(Text(labelNumber(x)).font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: vx, y: r.maxY + 12))
        }
        for y in niceTicks(lo: t.viewport.yLo, hi: t.viewport.yHi) {
            let vy = t.point(SpectrumPoint(x: t.viewport.xLo, y: y)).y
            var grid = Path()
            grid.move(to: CGPoint(x: r.minX, y: vy))
            grid.addLine(to: CGPoint(x: r.maxX, y: vy))
            ctx.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            ctx.draw(Text(labelNumber(y)).font(.caption2).foregroundStyle(.secondary),
                     at: CGPoint(x: r.minX - 26, y: vy))
        }
        // Axis titles
        if let first = visible.first {
            ctx.draw(Text(first.spectrum.xUnit.label).font(.caption),
                     at: CGPoint(x: r.midX, y: r.maxY + 26))
            let yTitle = normalize ? "Normalized"
                : plot.effectiveYUnit(for: first.spectrum).label
            var yctx = ctx
            yctx.translateBy(x: 14, y: r.midY)
            yctx.rotate(by: .degrees(-90))
            yctx.draw(Text(yTitle).font(.caption), at: .zero)
        }
    }

    private func labelNumber(_ v: Double) -> String {
        abs(v) >= 1000 || v == v.rounded()
            ? String(format: "%.0f", v) : String(format: "%.3g", v)
    }

    @ViewBuilder private var legend: some View {
        if appState.visibleSpectra.count > 1 {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(appState.visibleSpectra) { item in
                    HStack(spacing: 5) {
                        Rectangle().fill(item.color).frame(width: 14, height: 3)
                        Text(item.spectrum.title).font(.caption).lineLimit(1)
                    }
                }
            }
            .padding(6)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .padding(.top, 18)
            .padding(.trailing, 20)
        }
    }
}
