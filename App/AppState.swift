// App/AppState.swift
import SwiftUI
import SpectraKit

@MainActor @Observable
final class LoadedSpectrum: Identifiable {
    let id = UUID()
    let spectrum: Spectrum
    var isVisible = true
    var color: Color

    init(spectrum: Spectrum, color: Color) {
        self.spectrum = spectrum
        self.color = color
    }
}

struct LoadError: Identifiable {
    let id = UUID()
    var fileName: String
    var reason: String
}

@MainActor @Observable
final class AppState {
    var spectra: [LoadedSpectrum] = []
    var selectionID: UUID?
    var loadErrors: [LoadError] = []

    private static let palette: [Color] = [
        .blue, .red, .green, .orange, .purple, .teal, .pink, .indigo, .brown, .mint,
    ]
    private var colorCursor = 0

    var selected: LoadedSpectrum? {
        spectra.first { $0.id == selectionID }
    }
    var visibleSpectra: [LoadedSpectrum] {
        spectra.filter(\.isVisible)
    }

    func load(urls: [URL]) {
        for url in urls {
            do {
                let parsed = try SpectrumFile.read(url: url)
                for s in parsed {
                    let color = Self.palette[colorCursor % Self.palette.count]
                    colorCursor += 1
                    spectra.append(LoadedSpectrum(spectrum: s, color: color))
                }
                if selectionID == nil { selectionID = spectra.last?.id }
            } catch let e as SpectrumFileError {
                loadErrors.append(LoadError(fileName: url.lastPathComponent, reason: describe(e)))
            } catch let e as JCAMPError {
                loadErrors.append(LoadError(fileName: url.lastPathComponent, reason: describe(e)))
            } catch {
                loadErrors.append(LoadError(fileName: url.lastPathComponent,
                                      reason: error.localizedDescription))
            }
        }
    }

    func remove(_ id: UUID) {
        spectra.removeAll { $0.id == id }
        if selectionID == id { selectionID = spectra.first?.id }
    }

    private func describe(_ e: SpectrumFileError) -> String {
        switch e {
        case .unrecognizedFormat:
            "Not a recognized spectrum format (expected JCAMP-DX)."
        case .opusNotYetSupported:
            "This is a Bruker OPUS binary file — support is coming in a later version."
        case .unreadable(let why):
            "Couldn't read the file: \(why)"
        }
    }
    private func describe(_ e: JCAMPError) -> String {
        switch e {
        case .notJCAMP: "The file doesn't start with a JCAMP ##TITLE= record."
        case .unsupported(let what): "Unsupported JCAMP feature: \(what)"
        case .malformed(let what): "Malformed JCAMP data: \(what)"
        }
    }
}
