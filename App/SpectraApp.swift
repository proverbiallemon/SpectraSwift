// App/SpectraApp.swift
import SwiftUI
import SpectraKit
import UniformTypeIdentifiers

@main
struct SpectraApp: App {
    @State private var appState = AppState()
    @State private var plotModel = PlotModel()

    var body: some Scene {
        Window("Spectra DX", id: "main") {
            ContentView()
                .environment(appState)
                .environment(plotModel)
                .onOpenURL { url in
                    if url.pathExtension == "sdxsession" {
                        if let data = try? Data(contentsOf: url),
                           let file = try? SessionFile.decode(data) {
                            let missing = appState.restoreSession(file, plot: plotModel)
                            if !missing.isEmpty { presentMissing(missing) }
                        }
                    } else {
                        appState.load(urls: [url])
                    }
                }
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { openFiles() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Session…") {
                    SessionIO.save(appState.captureSession(plot: plotModel))
                }
                .keyboardShortcut("s")
                .disabled(appState.spectra.isEmpty)
                Button("Open Session…") {
                    guard let file = SessionIO.open() else { return }
                    let missing = appState.restoreSession(file, plot: plotModel)
                    if !missing.isEmpty { presentMissing(missing) }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Menu("Export") {
                    Button("CSV…") {
                        if let s = appState.selected?.spectrum {
                            ExportService.exportData(s, as: .csv)
                        }
                    }
                    .disabled(appState.selected == nil)
                    Button("JCAMP-DX…") {
                        if let s = appState.selected?.spectrum {
                            ExportService.exportData(s, as: .jcamp)
                        }
                    }
                    .disabled(appState.selected == nil)
                    Divider()
                    Button("Plot as PNG…") {
                        ExportService.exportImage(
                            ExportService.pngData(of: exportPlot, size: exportSize),
                            ext: "png", name: "plot.png")
                    }
                    .disabled(appState.spectra.isEmpty)
                    Button("Plot as PDF…") {
                        ExportService.exportImage(
                            ExportService.pdfData(of: exportPlot, size: exportSize),
                            ext: "pdf", name: "plot.pdf")
                    }
                    .disabled(appState.spectra.isEmpty)
                }
                Button("Copy Plot") {
                    ExportService.copyToPasteboard(
                        png: ExportService.pngData(of: exportPlot, size: exportSize))
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appState.spectra.isEmpty)
            }
            CommandMenu("Spectra") {
                Button("Subtract…") { appState.showSubtractSheet = true }
                    .disabled(appState.spectra.count < 2)
            }
            CommandGroup(after: .toolbar) {
                Button("Reset View") { plotModel.viewport = nil }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }

    private var exportSize: CGSize { CGSize(width: 900, height: 560) }
    private var exportPlot: some View {
        PlotView(interactive: false)
            .environment(appState)
            .environment(plotModel)
            .background(Color.white)
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
