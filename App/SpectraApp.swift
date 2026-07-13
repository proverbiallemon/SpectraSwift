// App/SpectraApp.swift
import SwiftUI
import UniformTypeIdentifiers

@main
struct SpectraApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("Spectra", id: "main") {
            ContentView()
                .environment(appState)
                .onOpenURL { appState.load(urls: [$0]) }
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { openFiles() }
                    .keyboardShortcut("o")
            }
        }
    }

    @MainActor private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "jdx") ?? .plainText,
            UTType(filenameExtension: "dx") ?? .plainText,
        ]
        if panel.runModal() == .OK {
            appState.load(urls: panel.urls)
        }
    }
}
