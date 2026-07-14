// App/ExportService.swift
import SwiftUI
import SpectraKit
import UniformTypeIdentifiers

@MainActor
enum ExportService {

    static func exportData(_ spectrum: Spectrum, as format: DataFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = suggestedName(spectrum, ext: format.ext)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = switch format {
        case .csv: CSVExporter.export(spectrum)
        case .jcamp: JCAMPExporter.export(spectrum)
        }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { presentError(error) }
    }

    enum DataFormat {
        case csv, jcamp
        var ext: String { self == .csv ? "csv" : "jdx" }
        var utType: UTType {
            self == .csv ? .commaSeparatedText
                         : (UTType(filenameExtension: "jdx") ?? .plainText)
        }
    }

    /// Renders `view` at `size` and returns PNG data.
    static func pngData<V: View>(of view: V, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width,
                                                         height: size.height))
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Renders `view` as vector PDF data.
    static func pdfData<V: View>(of view: V, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width,
                                                         height: size.height))
        let data = NSMutableData()
        renderer.render { rSize, render in
            var mediaBox = CGRect(origin: .zero, size: rSize)
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else { return }
            ctx.beginPDFPage(nil)
            render(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        return data as Data
    }

    static func exportImage(_ data: Data?, ext: String, name: String) {
        guard let data else {
            presentFailure("Couldn't render the plot image.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = ext == "png" ? [.png] : [.pdf]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url) } catch { presentError(error) }
    }

    static func copyToPasteboard(png: Data?) {
        guard let png else {
            presentFailure("Couldn't render the plot image.")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        if !pb.setData(png, forType: .png) {
            presentFailure("Couldn't write the plot image to the clipboard.")
        }
    }

    private static func suggestedName(_ s: Spectrum, ext: String) -> String {
        let base = s.title.isEmpty ? "spectrum" : s.title
        return base.replacingOccurrences(of: "/", with: "-") + "." + ext
    }

    private static func presentError(_ error: Error) {
        NSAlert(error: error).runModal()
    }

    private static func presentFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
