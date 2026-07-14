// App/AppState.swift
import SwiftUI
import SpectraKit

@MainActor @Observable
final class LoadedSpectrum: Identifiable {
    let id = UUID()
    let spectrum: Spectrum
    var isVisible = true
    var color: Color

    init(spectrum: Spectrum, color: Color) {
        self.spectrum = spectrum
        self.color = color
    }
}

struct LoadError: Identifiable {
    let id = UUID()
    var fileName: String
    var reason: String
}

@MainActor @Observable
final class AppState {
    var spectra: [LoadedSpectrum] = []
    var selectionID: UUID?
    var loadErrors: [LoadError] = []
    var peaks: [PeakMark] = []
    var regions: [IntegrationRegion] = []
    var statusText: String?   // transient refusals ("no spectrum selected")
    var showResultsTable = false
    var selectedResultIDs: Set<UUID> = []
    var showSubtractSheet = false

    private static let palette: [Color] = [
        .blue, .red, .green, .orange, .purple, .teal, .pink, .indigo, .brown, .mint,
    ]
    private var colorCursor = 0

    var selected: LoadedSpectrum? {
        spectra.first { $0.id == selectionID }
    }
    var visibleSpectra: [LoadedSpectrum] {
        spectra.filter(\.isVisible)
    }

    func load(urls: [URL]) {
        for url in urls {
            do {
                let parsed = try SpectrumFile.read(url: url)
                for s in parsed {
                    let color = Self.palette[colorCursor % Self.palette.count]
                    colorCursor += 1
                    spectra.append(LoadedSpectrum(spectrum: s, color: color))
                }
                if selectionID == nil { selectionID = spectra.last?.id }
            } catch let e as SpectrumFileError {
                loadErrors.append(LoadError(fileName: url.lastPathComponent, reason: describe(e)))
            } catch let e as JCAMPError {
                loadErrors.append(LoadError(fileName: url.lastPathComponent, reason: describe(e)))
            } catch {
                loadErrors.append(LoadError(fileName: url.lastPathComponent,
                                      reason: error.localizedDescription))
            }
        }
    }

    func addDerived(_ spectrum: Spectrum) {
        let color = Self.palette[colorCursor % Self.palette.count]
        colorCursor += 1
        let item = LoadedSpectrum(spectrum: spectrum, color: color)
        spectra.append(item)
        selectionID = item.id
    }

    func remove(_ id: UUID) {
        spectra.removeAll { $0.id == id }
        selectedResultIDs.subtract(Set(peaks.filter { $0.spectrumID == id }.map(\.id)))
        selectedResultIDs.subtract(Set(regions.filter { $0.spectrumID == id }.map(\.id)))
        peaks.removeAll { $0.spectrumID == id }
        regions.removeAll { $0.spectrumID == id }
        if selectionID == id { selectionID = spectra.first?.id }
    }

    func deletePeak(_ id: UUID) {
        peaks.removeAll { $0.id == id }
        selectedResultIDs.remove(id)
    }

    func deleteRegion(_ id: UUID) {
        regions.removeAll { $0.id == id }
        selectedResultIDs.remove(id)
    }

    /// True when visible spectra mix y-unit kinds and the plot normalizes
    /// each trace 0-1 for display. Mirrors PlotView's own `mustNormalize`
    /// (display-mode aware via `plot.effectiveYUnit(for:)`) so both the
    /// plot's rendering guard and AppState's measurement guards agree.
    func displayIsNormalized(plot: PlotModel) -> Bool {
        let units = Set(visibleSpectra.map { plot.effectiveYUnit(for: $0.spectrum).label })
        return units.count > 1
    }

    /// IDs of visible µm spectra that display unit-converted because a
    /// wavenumber spectrum is also visible.
    var convertedDisplayIDs: Set<UUID> {
        let visible = visibleSpectra
        let hasWavenumber = visible.contains {
            if case .wavenumber = $0.spectrum.xUnit { return true }
            return false
        }
        guard hasWavenumber else { return [] }
        return Set(visible.filter {
            if case .wavelengthUm = $0.spectrum.xUnit { return true }
            return false
        }.map(\.id))
    }

    /// The spectrum measurements apply to: explicit selection, else the
    /// only visible spectrum.
    var measurementTarget: LoadedSpectrum? {
        if let sel = selected, sel.isVisible { return sel }
        let vis = visibleSpectra
        return vis.count == 1 ? vis.first : nil
    }

    @discardableResult
    private func requireTarget() -> LoadedSpectrum? {
        guard let t = measurementTarget else {
            statusText = "Select a spectrum to measure"
            NSSound.beep()
            return nil
        }
        return t
    }

    func addPeak(at dataX: Double, plot: PlotModel) {
        guard let target = requireTarget() else { return }
        let pts = plot.effectivePoints(for: target.spectrum, normalize: false)
        let unit = plot.effectiveYUnit(for: target.spectrum)
        guard let apex = Measure.nearestPeak(
            in: pts, nearX: dataX,
            direction: plot.peakDirection(for: unit)) else {
            statusText = "No peak near that position"
            NSSound.beep()
            return
        }
        let mark = PeakMark(spectrumID: target.id, x: apex.x, y: apex.y,
                            height: baselineHeight(forPeakAt: apex.x, in: target,
                                                   points: pts, plot: plot),
                            displayMode: plot.displayMode.rawValue)
        guard !peaks.contains(where: {
            $0.spectrumID == mark.spectrumID && $0.x == mark.x
                && $0.displayMode == mark.displayMode }) else { return }
        peaks.append(mark)
        showResultsTable = true
    }

    /// Baseline rule: a peak inside an existing integration region (same
    /// spectrum, same display mode) measures its height against that
    /// region's chord. No region → no baseline → height is nil and the
    /// table simply omits it.
    private func baselineHeight(forPeakAt peakX: Double, in target: LoadedSpectrum,
                                points: [SpectrumPoint], plot: PlotModel) -> Double? {
        guard let region = regions.first(where: {
            $0.spectrumID == target.id
                && $0.displayMode == plot.displayMode.rawValue
                && (min($0.x1, $0.x2)...max($0.x1, $0.x2)).contains(peakX)
        }) else { return nil }
        return Measure.chordBaselineHeight(points: points, peakX: peakX,
                                           x1: region.x1, x2: region.x2)
    }

    func addRegion(x1: Double, x2: Double, plot: PlotModel) {
        guard let target = requireTarget() else { return }
        let pts = plot.effectivePoints(for: target.spectrum, normalize: false)
        do {
            let area = try Measure.integrate(points: pts, from: x1, to: x2)
            regions.append(IntegrationRegion(
                spectrumID: target.id, x1: x1, x2: x2, area: area,
                displayMode: plot.displayMode.rawValue))
            showResultsTable = true
        } catch {
            statusText = "That range contains no data to integrate"
            NSSound.beep()
        }
    }

    func autoDetectPeaks(plot: PlotModel) {
        guard !displayIsNormalized(plot: plot) else {
            statusText = "Mixed y-units are normalized for display — view this spectrum alone to measure"
            NSSound.beep()
            return
        }
        guard let target = requireTarget() else { return }
        // Same refusal as manual picking: detecting peaks in native µm space
        // while the trace displays converted would fill the table with marks
        // the plot simultaneously hides.
        guard !convertedDisplayIDs.contains(target.id) else {
            statusText = "This spectrum is shown unit-converted — view it alone to measure in its native units"
            NSSound.beep()
            return
        }
        let pts = plot.effectivePoints(for: target.spectrum, normalize: false)
        let unit = plot.effectiveYUnit(for: target.spectrum)
        let found = Measure.detectPeaks(
            in: pts, direction: plot.peakDirection(for: unit), minProminence: nil)
        // Replace prior auto-detected marks for this spectrum in this mode;
        // manual picks are indistinguishable, so the honest rule is:
        // deduplicate by (spectrum, x, mode) and add what's new.
        for apex in found {
            let mark = PeakMark(spectrumID: target.id, x: apex.x, y: apex.y,
                                height: nil, displayMode: plot.displayMode.rawValue)
            if !peaks.contains(where: {
                $0.spectrumID == mark.spectrumID && $0.x == mark.x
                    && $0.displayMode == mark.displayMode }) {
                peaks.append(mark)
            }
        }
        if !found.isEmpty { showResultsTable = true }
        statusText = found.isEmpty ? "No peaks found" : nil
    }

    func captureSession(plot: PlotModel) -> SessionFile {
        let refs = spectra.map { item -> SessionSpectrumRef in
            let rgba: SessionRGBA = {
                let ns = NSColor(item.color).usingColorSpace(.sRGB) ?? .black
                return SessionRGBA(r: ns.redComponent, g: ns.greenComponent,
                                   b: ns.blueComponent, a: ns.alphaComponent)
            }()
            if let url = item.spectrum.sourceURL {
                return SessionSpectrumRef(id: item.id, path: url.path,
                                          inline: nil, color: rgba,
                                          isVisible: item.isVisible,
                                          fingerprint: SessionSpectrumRef.fingerprint(of: item.spectrum))
            }
            return SessionSpectrumRef(id: item.id, path: nil,
                                      inline: SessionInlineSpectrum(from: item.spectrum),
                                      color: rgba, isVisible: item.isVisible)
        }
        return SessionFile(
            spectra: refs, peaks: peaks, regions: regions,
            viewport: plot.viewport.map {
                SessionViewportModel(xLo: $0.xLo, xHi: $0.xHi, yLo: $0.yLo, yHi: $0.yHi)
            },
            displayMode: plot.displayMode.rawValue,
            autoY: plot.autoY, selectedID: selectionID)
    }

    /// Replaces current state. Returns paths that no longer resolve, plus
    /// (appended to the same list) path-based sources whose on-disk content
    /// has changed since the session was saved — those spectra still load,
    /// but their marks/regions are stale x/y positions against a different
    /// curve, so they're dropped rather than silently mis-plotted.
    func restoreSession(_ file: SessionFile, plot: PlotModel) -> [String] {
        var missing: [String] = []
        var changedPaths: [String] = []
        var newSpectra: [LoadedSpectrum] = []
        var idMap: [UUID: UUID] = [:]   // session id → live LoadedSpectrum id
        var droppedMeasurementRefIDs: Set<UUID> = []   // session ids whose marks/regions are stale
        for ref in file.spectra {
            let spectrum: Spectrum?
            if let path = ref.path {
                spectrum = (try? SpectrumFile.read(url: URL(fileURLWithPath: path)))?.first
                if spectrum == nil {
                    missing.append(path)
                } else if let savedFingerprint = ref.fingerprint, let loaded = spectrum,
                          savedFingerprint != SessionSpectrumRef.fingerprint(of: loaded) {
                    changedPaths.append(path)
                    droppedMeasurementRefIDs.insert(ref.id)
                }
            } else {
                spectrum = ref.inline?.makeSpectrum()
            }
            guard let spectrum else { continue }
            let item = LoadedSpectrum(
                spectrum: spectrum,
                color: Color(.sRGB, red: ref.color.r, green: ref.color.g,
                             blue: ref.color.b, opacity: ref.color.a))
            item.isVisible = ref.isVisible
            idMap[ref.id] = item.id
            newSpectra.append(item)
        }
        spectra = newSpectra
        let droppedLiveIDs = Set(droppedMeasurementRefIDs.compactMap { idMap[$0] })
        peaks = file.peaks.compactMap { p in
            guard let live = idMap[p.spectrumID], !droppedLiveIDs.contains(live) else { return nil }
            var copy = p; copy.spectrumID = live; return copy
        }
        regions = file.regions.compactMap { r in
            guard let live = idMap[r.spectrumID], !droppedLiveIDs.contains(live) else { return nil }
            var copy = r; copy.spectrumID = live; return copy
        }
        selectionID = file.selectedID.flatMap { idMap[$0] } ?? spectra.first?.id
        plot.viewport = file.viewport.map {
            PlotViewport(xLo: $0.xLo, xHi: $0.xHi, yLo: $0.yLo, yHi: $0.yHi)
        }
        plot.displayMode = IRDisplayMode(rawValue: file.displayMode) ?? .native
        plot.autoY = file.autoY
        plot.mode = .explore
        showResultsTable = !peaks.isEmpty || !regions.isEmpty
        selectedResultIDs = []
        statusText = nil
        return missing + changedPaths.map {
            "\($0) (file changed since the session was saved — its measurements were dropped)"
        }
    }

    private func describe(_ e: SpectrumFileError) -> String {
        switch e {
        case .unrecognizedFormat:
            "Not a recognized spectrum format (expected JCAMP-DX)."
        case .opusNotYetSupported:
            "This is a Bruker OPUS binary file — support is coming in a later version."
        case .unreadable(let why):
            "Couldn't read the file: \(why)"
        }
    }
    private func describe(_ e: JCAMPError) -> String {
        switch e {
        case .notJCAMP: "The file doesn't start with a JCAMP ##TITLE= record."
        case .unsupported(let what): "Unsupported JCAMP feature: \(what)"
        case .malformed(let what): "Malformed JCAMP data: \(what)"
        }
    }
}
