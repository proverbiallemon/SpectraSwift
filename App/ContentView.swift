// App/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlotModel.self) private var plotModel
    @State private var showInspector = true

    var body: some View {
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
                PlotView()
                    .environment(plotModel)
                    .inspector(isPresented: $showInspector) {
                        InspectorView()
                            .inspectorColumnWidth(min: 220, ideal: 280)
                    }
                    .toolbar {
                        ToolbarItem {
                            Button { showInspector.toggle() } label: {
                                Label("Inspector", systemImage: "sidebar.right")
                            }
                        }
                    }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            appState.load(urls: urls)
            return true
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
