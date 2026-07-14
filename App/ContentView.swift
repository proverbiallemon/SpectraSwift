// App/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlotModel.self) private var plotModel
    @State private var showInspector = true

    var body: some View {
        @Bindable var plot = plotModel
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
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
                    .inspector(isPresented: $showInspector) {
                        InspectorView()
                            .inspectorColumnWidth(min: 220, ideal: 280)
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
            appState.load(urls: fileURLs)
            return !fileURLs.isEmpty
        }
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
}
