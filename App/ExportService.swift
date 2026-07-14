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
        let result = data as Data
        return result.isEmpty ? nil : result
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

    static func resultsTSV(peaks: [PeakMark], regions: [IntegrationRegion],
                           spectrumTitles: [UUID: String]) -> String {
        var out = ""
        if !peaks.isEmpty {
            out += "Type\tSpectrum\tX\tY\tHeight\tMeasured as\n"
            for p in peaks {
                out += "Peak\t\(spectrumTitles[p.spectrumID] ?? "removed")\t\(p.x)\t\(p.y)\t\(p.height.map { String($0) } ?? "")\t\(p.displayMode)\n"
            }
        }
        if !regions.isEmpty {
            out += "Type\tSpectrum\tX1\tX2\tArea\tMeasured as\n"
            for r in regions {
                out += "Area\t\(spectrumTitles[r.spectrumID] ?? "removed")\t\(r.x1)\t\(r.x2)\t\(r.area)\t\(r.displayMode)\n"
            }
        }
        return out
    }

    /// Builds a proper CSV (rows as arrays, fields quoted per RFC 4180) rather
    /// than converting the TSV with a naive tab→comma replace, since spectrum
    /// titles can themselves contain commas or quotes.
    static func resultsCSV(peaks: [PeakMark], regions: [IntegrationRegion],
                           spectrumTitles: [UUID: String]) -> String {
        var out = ""
        if !peaks.isEmpty {
            out += csvRow(["Type", "Spectrum", "X", "Y", "Height", "Measured as"])
            for p in peaks {
                out += csvRow([
                    "Peak", spectrumTitles[p.spectrumID] ?? "removed",
                    String(p.x), String(p.y),
                    p.height.map { String($0) } ?? "", p.displayMode,
                ])
            }
        }
        if !regions.isEmpty {
            out += csvRow(["Type", "Spectrum", "X1", "X2", "Area", "Measured as"])
            for r in regions {
                out += csvRow([
                    "Area", spectrumTitles[r.spectrumID] ?? "removed",
                    String(r.x1), String(r.x2), String(r.area), r.displayMode,
                ])
            }
        }
        return out
    }

    private static func csvField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func csvRow(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",") + "\n"
    }

    static func exportResultsCSV(peaks: [PeakMark], regions: [IntegrationRegion],
                                 spectrumTitles: [UUID: String]) {
        let csv = resultsCSV(peaks: peaks, regions: regions,
                             spectrumTitles: spectrumTitles)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "measurements.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try csv.write(to: url, atomically: true, encoding: .utf8) }
        catch { presentError(error) }
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

@MainActor
enum SessionIO {
    static let utType = UTType(exportedAs: "me.pbweb.spectra.session")

    static func save(_ file: SessionFile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [utType]
        panel.nameFieldStringValue = "Untitled.sdxsession"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try file.encoded().write(to: url) }
        catch { NSAlert(error: error).runModal() }
    }

    static func open() -> SessionFile? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [utType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do { return try SessionFile.decode(Data(contentsOf: url)) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't open session"
            alert.informativeText = "\(url.lastPathComponent) isn't a readable Spectra DX session: \(error.localizedDescription)"
            alert.runModal()
            return nil
        }
    }
}
