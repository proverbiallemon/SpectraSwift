// App/PlotView.swift
import SwiftUI
import SpectraKit

struct PlotView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlotModel.self) private var plot

    @State private var dragRect: CGRect?       // rubber-band in view coords
    @State private var lastTransform: PlotTransform?
    @State private var scrollMonitor: Any?
    @State private var panStartViewport: PlotViewport?
    @State private var viewFrame: CGRect = .zero
    @State private var magnifyStartViewport: PlotViewport?

    var interactive: Bool = true

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
            let sets = plot.pointSets(for: visible, normalize: normalize)
            guard let vp = plot.viewport ?? PlotViewport.fitting(sets) else { return }
            let t = PlotTransform(viewport: vp, size: size,
                                  inset: inset, xReversed: xReversed)

            drawAxes(ctx, t, normalize: normalize, visible: visible)
            ctx.clip(to: Path(t.plotRect))
            for (item, pts) in zip(visible, sets) {
                draw(pts, form: item.spectrum.dataForm,
                     color: item.color, in: ctx, transform: t)
            }
            drawMeasurements(ctx, t, visible: visible)

            let captured = t
            if lastTransform != captured {
                DispatchQueue.main.async { lastTransform = captured }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { viewFrame = $0 }
        .overlay(alignment: .topTrailing) { legend }
        .overlay { rubberBand }
        .overlay { crosshairOverlay }
        .overlay(alignment: .bottom) { statusCapsule }
        .gesture(measurementTap, including: plot.mode == .explore ? .subviews : .all)
        .gesture(boxZoomOrPan)
        .simultaneousGesture(pinchZoom)
        .onTapGesture(count: 2) { plot.viewport = nil }   // reset to auto-fit
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): plot.crosshair = p
            case .ended: plot.crosshair = nil
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("Y Display", selection: Bindable(plot).displayMode) {
                    ForEach(IRDisplayMode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .help("Convert IR spectra between transmittance and absorbance")
            }
            ToolbarItem {
                Button {
                    plot.viewport = nil
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Zoom to fit all visible spectra")
            }
        }
        .onAppear {
            guard interactive, scrollMonitor == nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { ev in
                guard let t = lastTransform,
                      let window = ev.window,
                      let contentView = window.contentView else { return ev }
                let inContent = contentView.convert(ev.locationInWindow, from: nil)
                // flip to SwiftUI top-left coords, then into PlotView-local space
                let topLeft = CGPoint(x: inContent.x,
                                      y: contentView.bounds.height - inContent.y)
                let p = CGPoint(x: topLeft.x - viewFrame.minX,
                                y: topLeft.y - viewFrame.minY)
                guard t.plotRect.insetBy(dx: -20, dy: -20).contains(p) else { return ev }
                let factor = ev.scrollingDeltaY > 0 ? 1.1 : 1 / 1.1
                let vp = plot.viewport ?? currentFit()
                guard let vp else { return ev }
                var fx = (p.x - t.plotRect.minX) / t.plotRect.width
                if t.xReversed { fx = 1 - fx }
                let fy = (t.plotRect.maxY - p.y) / t.plotRect.height
                plot.viewport = vp.zoomed(by: factor, aboutX: fx, aboutY: fy)
                return nil
            }
        }
        .onDisappear {
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
        }
        .background {
            // SwiftUI's onKeyPress + .focusable() can't reliably reclaim
            // first-responder status from a toolbar control (segmented
            // picker, button) on macOS, so Escape would silently no-op
            // after using the mode picker. A hidden keyboardShortcut button
            // uses the same window-wide key-equivalent dispatch that makes
            // menu shortcuts (e.g. Cmd-O) work regardless of what has focus.
            Button("") {
                if plot.pendingX1 != nil { plot.pendingX1 = nil }
                else if plot.mode != .explore { plot.mode = .explore }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
        }
    }

    private var measurementTap: some Gesture {
        SpatialTapGesture()
            .onEnded { g in
                guard plot.mode != .explore, let t = lastTransform,
                      t.plotRect.contains(g.location) else { return }
                let d = t.dataXY(at: g.location)
                switch plot.mode {
                case .pickPeaks:
                    appState.addPeak(at: d.x, plot: plot)
                case .integrate:
                    if let x1 = plot.pendingX1 {
                        appState.addRegion(x1: x1, x2: d.x, plot: plot)
                        plot.pendingX1 = nil
                    } else {
                        plot.pendingX1 = d.x
                    }
                case .explore:
                    break
                }
            }
    }

    private var boxZoomOrPan: some Gesture {
        DragGesture(minimumDistance: 4)
            .modifiers(.option)
            .onChanged { g in
                guard plot.mode == .explore, let t = lastTransform else { return }
                if panStartViewport == nil {
                    panStartViewport = plot.viewport ?? currentFit()
                }
                guard let base = panStartViewport else { return }
                let dxFrac = -Double(g.translation.width) / t.plotRect.width
                    * (t.xReversed ? -1 : 1)
                let dyFrac = Double(g.translation.height) / t.plotRect.height
                plot.viewport = base.panned(fractionX: dxFrac, fractionY: dyFrac)
            }
            .onEnded { _ in guard plot.mode == .explore else { return }; panStartViewport = nil }
            .exclusively(before:
                DragGesture(minimumDistance: 4)
                    .onChanged { g in
                        guard plot.mode == .explore else { return }
                        dragRect = CGRect(
                            x: min(g.startLocation.x, g.location.x),
                            y: min(g.startLocation.y, g.location.y),
                            width: abs(g.translation.width),
                            height: abs(g.translation.height))
                    }
                    .onEnded { g in
                        defer { dragRect = nil }
                        guard plot.mode == .explore, let t = lastTransform,
                              let rect = dragRect,
                              rect.width > 8, rect.height > 8 else { return }
                        let a = t.dataXY(at: CGPoint(x: rect.minX, y: rect.maxY))
                        let b = t.dataXY(at: CGPoint(x: rect.maxX, y: rect.minY))
                        plot.viewport = PlotViewport(
                            xLo: min(a.x, b.x), xHi: max(a.x, b.x),
                            yLo: min(a.y, b.y), yHi: max(a.y, b.y))
                    })
    }

    private var pinchZoom: some Gesture {
        MagnifyGesture()
            .onChanged { g in
                guard let t = lastTransform else { return }
                if magnifyStartViewport == nil {
                    magnifyStartViewport = plot.viewport ?? currentFit()
                }
                guard let base = magnifyStartViewport else { return }
                let p = g.startLocation
                guard t.plotRect.contains(p) else { return }
                var fx = (p.x - t.plotRect.minX) / t.plotRect.width
                if t.xReversed { fx = 1 - fx }
                let fy = (t.plotRect.maxY - p.y) / t.plotRect.height
                plot.viewport = base.zoomed(by: Double(g.magnification), aboutX: fx, aboutY: fy)
            }
            .onEnded { _ in magnifyStartViewport = nil }
    }

    /// Nearest visible data point to a view-space location, within a 24pt hit radius.
    private func nearestPoint(to p: CGPoint, transform t: PlotTransform)
        -> (point: SpectrumPoint, color: Color)? {
        let visible = appState.visibleSpectra
        let sets = plot.pointSets(for: visible, normalize: mustNormalize)
        var best: (SpectrumPoint, Color, CGFloat)? = nil
        for (item, pts) in zip(visible, sets) {
            for pt in pts {
                let v = t.point(pt)
                let d = hypot(v.x - p.x, v.y - p.y)
                if d < (best?.2 ?? 24) { best = (pt, item.color, d) }
            }
        }
        return best.map { ($0.0, $0.1) }
    }

    private func currentFit() -> PlotViewport? {
        let normalize = mustNormalize
        return PlotViewport.fitting(plot.pointSets(for: appState.visibleSpectra, normalize: normalize))
    }

    @ViewBuilder private var statusCapsule: some View {
        if let status = appState.statusText {
            Text(status)
                .font(.callout)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 46)
                .task {
                    try? await Task.sleep(for: .seconds(2.5))
                    appState.statusText = nil
                }
        }
    }

    @ViewBuilder private var rubberBand: some View {
        if let r = dragRect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var crosshairOverlay: some View {
        if let p = plot.crosshair, let t = lastTransform, t.plotRect.contains(p) {
            let snap = nearestPoint(to: p, transform: t)
            let markerPoint = snap.map { t.point($0.point) } ?? p
            let d = snap.map { ($0.point.x, $0.point.y) } ?? t.dataXY(at: p)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: markerPoint.x, y: t.plotRect.minY))
                    path.addLine(to: CGPoint(x: markerPoint.x, y: t.plotRect.maxY))
                    path.move(to: CGPoint(x: t.plotRect.minX, y: markerPoint.y))
                    path.addLine(to: CGPoint(x: t.plotRect.maxX, y: markerPoint.y))
                }
                .stroke(Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                if let snap {
                    Circle()
                        .fill(snap.color)
                        .frame(width: 6, height: 6)
                        .position(markerPoint)
                }
                Text("\(labelNumber(d.0)), \(String(format: "%.4g", d.1))")
                    .font(.caption.monospacedDigit())
                    .padding(4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .position(x: min(markerPoint.x + 60, t.plotRect.maxX - 50),
                              y: max(markerPoint.y - 18, 24))
            }
            .allowsHitTesting(false)
        }
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

    private func drawMeasurements(_ ctx: GraphicsContext, _ t: PlotTransform,
                                  visible: [LoadedSpectrum]) {
        guard !mustNormalize else { return }
        let visibleIDs = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0.color) })
        for mark in appState.peaks
        where mark.displayMode == plot.displayMode.rawValue {
            guard let color = visibleIDs[mark.spectrumID] else { continue }
            let v = t.point(SpectrumPoint(x: mark.x, y: mark.y))
            let r = CGRect(x: v.x - 4, y: v.y - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: r), with: .color(color))
            ctx.stroke(Path(ellipseIn: r.insetBy(dx: -2, dy: -2)),
                       with: .color(color.opacity(0.5)), lineWidth: 1)
            if appState.selectedResultIDs.contains(mark.id) {
                ctx.stroke(Path(ellipseIn: r.insetBy(dx: -5, dy: -5)),
                           with: .color(.primary), lineWidth: 1.5)
            }
        }
        for region in appState.regions
        where region.displayMode == plot.displayMode.rawValue {
            guard let color = visibleIDs[region.spectrumID],
                  let item = visible.first(where: { $0.id == region.spectrumID })
            else { continue }
            let pts = plot.effectivePoints(for: item.spectrum, normalize: false)
                .filter { $0.x >= region.x1 && $0.x <= region.x2 }
                .sorted { $0.x < $1.x }
            guard pts.count >= 2 else { continue }
            var path = Path()
            path.move(to: t.point(pts[0]))
            for p in pts.dropFirst() { path.addLine(to: t.point(p)) }
            path.addLine(to: t.point(pts[pts.count - 1]))
            path.closeSubpath()
            ctx.fill(path, with: .color(color.opacity(0.18)))
            var chord = Path()
            chord.move(to: t.point(pts[0]))
            chord.addLine(to: t.point(pts[pts.count - 1]))
            if appState.selectedResultIDs.contains(region.id) {
                ctx.stroke(chord, with: .color(color.opacity(0.9)), lineWidth: 2)
            } else {
                ctx.stroke(chord, with: .color(color.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        // Pending first integration click: vertical guide line.
        if plot.mode == .integrate, let x1 = plot.pendingX1 {
            let vx = t.point(SpectrumPoint(x: x1, y: t.viewport.yLo)).x
            var guide = Path()
            guide.move(to: CGPoint(x: vx, y: t.plotRect.minY))
            guide.addLine(to: CGPoint(x: vx, y: t.plotRect.maxY))
            ctx.stroke(guide, with: .color(.secondary),
                       style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
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
