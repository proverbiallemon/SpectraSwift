// App/ResultsTableView.swift
import SwiftUI
import SpectraKit

struct ResultsTableView: View {
    @Environment(AppState.self) private var appState

    private func title(for id: UUID) -> String {
        appState.spectra.first { $0.id == id }?.spectrum.title ?? "removed"
    }
    private func sig4(_ v: Double) -> String { String(format: "%.4g", v) }

    var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            HStack {
                Text("Results").font(.headline)
                Spacer()
                Button("Copy") { copySelection() }
                    .disabled(appState.peaks.isEmpty && appState.regions.isEmpty)
                Button("Export CSV…") {
                    ExportService.exportResultsCSV(
                        peaks: appState.peaks, regions: appState.regions,
                        spectrumTitles: titlesByID)
                }
                .disabled(appState.peaks.isEmpty && appState.regions.isEmpty)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            List(selection: $state.selectedResultIDs) {
                if !appState.peaks.isEmpty {
                    Section("Peaks") {
                        ForEach(appState.peaks) { p in
                            HStack {
                                Text(title(for: p.spectrumID)).frame(maxWidth: 150, alignment: .leading).lineLimit(1)
                                Text("x \(sig4(p.x))").monospacedDigit()
                                Text("y \(sig4(p.y))").monospacedDigit()
                                if let h = p.height {
                                    Text("h \(sig4(h))").monospacedDigit()
                                }
                                Spacer()
                                Text(p.displayMode).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(p.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    appState.peaks.removeAll { $0.id == p.id }
                                }
                            }
                        }
                    }
                }
                if !appState.regions.isEmpty {
                    Section("Areas") {
                        ForEach(appState.regions) { r in
                            HStack {
                                Text(title(for: r.spectrumID)).frame(maxWidth: 150, alignment: .leading).lineLimit(1)
                                Text("\(sig4(r.x1)) – \(sig4(r.x2))").monospacedDigit()
                                Text("area \(sig4(r.area))").monospacedDigit()
                                Spacer()
                                Text(r.displayMode).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(r.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    appState.regions.removeAll { $0.id == r.id }
                                }
                            }
                        }
                    }
                }
            }
            .onDeleteCommand {
                appState.peaks.removeAll { appState.selectedResultIDs.contains($0.id) }
                appState.regions.removeAll { appState.selectedResultIDs.contains($0.id) }
                appState.selectedResultIDs.removeAll()
            }
        }
    }

    private var titlesByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: appState.spectra.map {
            ($0.id, $0.spectrum.title)
        })
    }

    private func copySelection() {
        let ids = appState.selectedResultIDs
        let peaks = ids.isEmpty ? appState.peaks
            : appState.peaks.filter { ids.contains($0.id) }
        let regions = ids.isEmpty ? appState.regions
            : appState.regions.filter { ids.contains($0.id) }
        let tsv = ExportService.resultsTSV(peaks: peaks, regions: regions,
                                           spectrumTitles: titlesByID)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tsv, forType: .string)
    }
}
