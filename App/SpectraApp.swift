// App/SpectraApp.swift
import SwiftUI
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
                .onOpenURL { appState.load(urls: [$0]) }
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { openFiles() }
                    .keyboardShortcut("o")
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
}
