import Foundation

public struct PeakMark: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var spectrumID: UUID
    public var x: Double
    public var y: Double
    public var height: Double?
    public var displayMode: String

    public init(id: UUID = UUID(), spectrumID: UUID, x: Double, y: Double,
                height: Double?, displayMode: String) {
        self.id = id; self.spectrumID = spectrumID; self.x = x; self.y = y
        self.height = height; self.displayMode = displayMode
    }
}

public struct IntegrationRegion: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var spectrumID: UUID
    public var x1: Double
    public var x2: Double
    public var area: Double
    public var displayMode: String

    public init(id: UUID = UUID(), spectrumID: UUID, x1: Double, x2: Double,
                area: Double, displayMode: String) {
        self.id = id; self.spectrumID = spectrumID
        self.x1 = min(x1, x2); self.x2 = max(x1, x2)
        self.area = area; self.displayMode = displayMode
    }
}

public struct SessionRGBA: Sendable, Codable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

public struct SessionInlineSpectrum: Sendable, Codable {
    public var title: String
    public var xUnit: XUnit
    public var yUnit: YUnit
    public var dataForm: DataForm
    public var points: [SpectrumPoint]

    public init(title: String, xUnit: XUnit, yUnit: YUnit,
                dataForm: DataForm, points: [SpectrumPoint]) {
        self.title = title; self.xUnit = xUnit; self.yUnit = yUnit
        self.dataForm = dataForm; self.points = points
    }

    public init(from s: Spectrum) {
        self.init(title: s.title, xUnit: s.xUnit, yUnit: s.yUnit,
                  dataForm: s.dataForm, points: s.points)
    }

    public func makeSpectrum() -> Spectrum {
        Spectrum(title: title, origin: "", owner: "", sourceURL: nil,
                 xUnit: xUnit, yUnit: yUnit, dataForm: dataForm,
                 points: points, parameters: [],
                 warnings: [])
    }
}

public struct SessionSpectrumRef: Sendable, Codable, Identifiable {
    public var id: UUID
    public var path: String?
    public var inline: SessionInlineSpectrum?
    public var color: SessionRGBA
    public var isVisible: Bool

    public init(id: UUID, path: String?, inline: SessionInlineSpectrum?,
                color: SessionRGBA, isVisible: Bool) {
        self.id = id; self.path = path; self.inline = inline
        self.color = color; self.isVisible = isVisible
    }
}

public struct SessionViewportModel: Sendable, Codable, Equatable {
    public var xLo: Double, xHi: Double, yLo: Double, yHi: Double
    public init(xLo: Double, xHi: Double, yLo: Double, yHi: Double) {
        self.xLo = xLo; self.xHi = xHi; self.yLo = yLo; self.yHi = yHi
    }
}

public struct SessionFile: Sendable, Codable {
    public var version: Int
    public var spectra: [SessionSpectrumRef]
    public var peaks: [PeakMark]
    public var regions: [IntegrationRegion]
    public var viewport: SessionViewportModel?
    public var displayMode: String
    public var autoY: Bool
    public var selectedID: UUID?

    public init(version: Int = 1, spectra: [SessionSpectrumRef],
                peaks: [PeakMark], regions: [IntegrationRegion],
                viewport: SessionViewportModel?, displayMode: String,
                autoY: Bool, selectedID: UUID?) {
        self.version = version; self.spectra = spectra; self.peaks = peaks
        self.regions = regions; self.viewport = viewport
        self.displayMode = displayMode; self.autoY = autoY
        self.selectedID = selectedID
    }

    public func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(self)
    }

    public static func decode(_ data: Data) throws -> SessionFile {
        try JSONDecoder().decode(SessionFile.self, from: data)
    }
}
