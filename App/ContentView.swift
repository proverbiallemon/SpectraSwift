// App/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
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
                Text("Plot goes here")   // replaced in Task 8
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            appState.load(urls: urls)
            return true
        }
        .alert(item: $state.loadError) { err in
            Alert(title: Text("Couldn't open \(err.fileName)"),
                  message: Text(err.reason))
        }
    }
}
