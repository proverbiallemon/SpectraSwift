// App/ContentView.swift
import SwiftUI
import SpectraKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlotModel.self) private var plotModel
    @State private var showInspector = true

    var body: some View {
        @Bindable var plot = plotModel
        @Bindable var state = appState
        NavigationSplitView {
            SidebarView()
                // The max width is load-bearing: without it, dragging the
                // divider could inflate the sidebar without bound, and the
                // resulting layout fight once locked up the whole machine.
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            if appState.spectra.isEmpty {
                ContentUnavailableView(
                    "No Spectra",
                    systemImage: "waveform.path",
                    description: Text("Open or drop JCAMP-DX (.jdx, .dx) files to view them."))
            } else {
                VSplitView {
                    PlotView()
                        .environment(plotModel)
                        .frame(minHeight: 240)
                    if appState.showResultsTable {
                        ResultsTableView()
                            .frame(minHeight: 120, idealHeight: 180, maxHeight: 320)
                    }
                }
                    .frame(minWidth: 420)
                    .inspector(isPresented: $showInspector) {
                        InspectorView()
                            // Bounded on BOTH sides, like the sidebar: any
                            // unbounded pane width lets the layout engine
                            // recurse itself to death during divider drags.
                            .inspectorColumnWidth(min: 220, ideal: 280, max: 420)
                    }
                    .toolbar {
                        ToolbarItem {
                            Picker("Mode", selection: $plot.mode) {
                                ForEach(PlotMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .help("Explore pans and zooms; Pick Peaks and Integrate turn clicks into measurements")
                        }
                        ToolbarItem {
                            Button("Find Peaks") { appState.autoDetectPeaks(plot: plotModel) }
                                .disabled(plotModel.mode != .pickPeaks)
                                .help("Automatically find peaks in the selected spectrum")
                        }
                        ToolbarItem {
                            Button {
                                appState.showResultsTable.toggle()
                            } label: {
                                Label("Results", systemImage: "tablecells")
                            }
                            .help("Show or hide the measurements table")
                            .keyboardShortcut("t", modifiers: [.command, .shift])
                        }
                        ToolbarItem {
                            Button { showInspector.toggle() } label: {
                                Label("Inspector", systemImage: "sidebar.right")
                            }
                        }
                    }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let fileURLs = urls.filter(\.isFileURL)
            let sessionURLs = fileURLs.filter { $0.pathExtension == "spectrasession" }
            let spectrumURLs = fileURLs.filter { $0.pathExtension != "spectrasession" }
            for url in sessionURLs {
                if let file = SessionIO.openSession(at: url) {
                    let missing = appState.restoreSession(file, plot: plotModel)
                    if !missing.isEmpty { presentMissing(missing) }
                }
            }
            appState.load(urls: spectrumURLs)
            return !fileURLs.isEmpty
        }
        .sheet(isPresented: $state.showSubtractSheet) { SubtractSheetView() }
        .sheet(isPresented: $state.showSmoothSheet) { SmoothSheetView() }
        .alert(
            appState.loadErrors.count == 1
                ? "Couldn't open \(appState.loadErrors[0].fileName)"
                : "Couldn't open \(appState.loadErrors.count) files",
            isPresented: Binding(
                get: { !appState.loadErrors.isEmpty },
                set: { if !$0 { appState.loadErrors.removeAll() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.loadErrors
                .map { "\($0.fileName): \($0.reason)" }
                .joined(separator: "\n"))
        }
    }

    @MainActor private func presentMissing(_ paths: [String]) {
        let alert = NSAlert()
        alert.messageText = paths.count == 1
            ? "One file couldn't be found"
            : "\(paths.count) files couldn't be found"
        alert.informativeText = "The rest of the session loaded. Missing:\n"
            + paths.joined(separator: "\n")
        alert.runModal()
    }
}
