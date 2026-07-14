// App/SmoothSheetView.swift
import SwiftUI
import SpectraKit

struct SmoothSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var spectrumID: UUID?
    @State private var window: Int = 11
    @State private var polyOrder: Int = 2
    @State private var errorText: String?
    @State private var rawPreview: [SpectrumPoint] = []
    @State private var smoothedPreview: [SpectrumPoint] = []

    private var selected: LoadedSpectrum? {
        appState.spectra.first { $0.id == spectrumID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smooth Spectrum").font(.headline)
            Picker("Spectrum:", selection: $spectrumID) {
                ForEach(appState.spectra) { s in
                    Text(s.spectrum.title).tag(Optional(s.id))
                }
            }
            Stepper("Window: \(window)", value: $window, in: 5...25, step: 2)
            Picker("Order:", selection: $polyOrder) {
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .pickerStyle(.segmented)

            Canvas { ctx, size in drawPreview(ctx: ctx, size: size) }
                .frame(width: 380, height: 120)
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.secondary.opacity(0.3))

            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Smooth") { smooth() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(spectrumID == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            spectrumID = appState.selectionID ?? appState.spectra.first?.id
            recomputePreview()
        }
        .onChange(of: spectrumID) { recomputePreview() }
        .onChange(of: window) { recomputePreview() }
        .onChange(of: polyOrder) { recomputePreview() }
    }

    /// Recomputes the display-only preview traces. Never mutates the
    /// underlying spectrum; the Canvas closure itself only draws from
    /// these already-computed arrays, so it stays pure.
    private func recomputePreview() {
        guard let s = selected?.spectrum else {
            rawPreview = []
            smoothedPreview = []
            errorText = nil
            return
        }
        rawPreview = Self.downsample(s.points, maxCount: 600)
        do {
            let candidate = try Smooth.savitzkyGolay(s, window: window, polyOrder: polyOrder)
            smoothedPreview = Self.downsample(candidate.points, maxCount: 600)
            errorText = nil
        } catch {
            smoothedPreview = []
            errorText = message(for: error)
        }
    }

    private func smooth() {
        guard let s = selected?.spectrum else { return }
        do {
            let result = try Smooth.savitzkyGolay(s, window: window, polyOrder: polyOrder)
            appState.addDerived(result)
            dismiss()
        } catch {
            errorText = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case SmoothError.invalidParameters(let why):
            return why
        case SmoothError.tooFewPoints(let needed, let have):
            return "This spectrum has \(have) points, but a window of \(needed) needs at least that many."
        case SmoothError.stickData:
            return "Stick spectra (like mass spectra) can't be smoothed."
        default:
            return error.localizedDescription
        }
    }

    private func drawPreview(ctx: GraphicsContext, size: CGSize) {
        guard !rawPreview.isEmpty else { return }
        let allYs = (rawPreview + smoothedPreview).map(\.y)
        let xs = rawPreview.map(\.x)
        guard let xLo = xs.min(), let xHi = xs.max(), xHi > xLo,
              let yLo = allYs.min(), let yHi = allYs.max(), yHi > yLo else { return }
        let reversed = selected?.spectrum.xUnit.isConventionallyReversed ?? false

        func plot(_ p: SpectrumPoint) -> CGPoint {
            let fx = (p.x - xLo) / (xHi - xLo)
            let fy = (p.y - yLo) / (yHi - yLo)
            let px = reversed ? 1 - fx : fx
            return CGPoint(x: px * size.width, y: size.height - fy * size.height)
        }

        func stroke(_ points: [SpectrumPoint], color: Color, lineWidth: CGFloat) {
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: plot(first))
            for p in points.dropFirst() { path.addLine(to: plot(p)) }
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
        }

        stroke(rawPreview, color: .gray, lineWidth: 1)
        stroke(smoothedPreview, color: .accentColor, lineWidth: 1.5)
    }

    /// Evenly-spaced downsample so the preview polyline stays snappy even
    /// for spectra with thousands of points. Display-only.
    private static func downsample(_ points: [SpectrumPoint], maxCount: Int) -> [SpectrumPoint] {
        guard points.count > maxCount, maxCount > 1 else { return points }
        let stride = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { i in points[Int((Double(i) * stride).rounded())] }
    }
}
