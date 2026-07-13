import Foundation

public struct SpectrumPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// How the data should be rendered.
public enum DataForm: Sendable, Equatable {
    case continuous   // IR, UV-Vis, Raman, THz — polyline
    case peaks        // mass spec — vertical sticks
}

public enum XUnit: Sendable, Equatable {
    case wavenumber          // 1/CM
    case wavelengthNm        // NANOMETERS
    case wavelengthUm        // MICROMETERS
    case massCharge          // M/Z
    case seconds
    case other(String)

    public var label: String {
        switch self {
        case .wavenumber: "Wavenumber (cm⁻¹)"
        case .wavelengthNm: "Wavelength (nm)"
        case .wavelengthUm: "Wavelength (µm)"
        case .massCharge: "m/z"
        case .seconds: "Time (s)"
        case .other(let s): s
        }
    }

    /// IR convention: wavenumber axes are drawn high→low.
    public var isConventionallyReversed: Bool {
        if case .wavenumber = self { return true }
        return false
    }
}

public enum YUnit: Sendable, Equatable {
    case transmittance
    case absorbance
    case relativeIntensity
    case other(String)

    public var label: String {
        switch self {
        case .transmittance: "Transmittance"
        case .absorbance: "Absorbance"
        case .relativeIntensity: "Relative Intensity"
        case .other(let s): s
        }
    }
}

/// A recoverable oddity found while parsing. Shown as a ⚠️ badge in the UI.
public struct SpectrumWarning: Sendable, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

/// One ##LABEL= record from the source file, preserved in file order.
public struct Parameter: Sendable, Equatable, Identifiable {
    public var key: String
    public var value: String
    public var id: String { key + "=" + value }
    public init(key: String, value: String) { self.key = key; self.value = value }
}

public struct Spectrum: Sendable, Identifiable {
    public let id = UUID()
    public var title: String
    public var origin: String
    public var owner: String
    public var sourceURL: URL?
    public var xUnit: XUnit
    public var yUnit: YUnit
    public var dataForm: DataForm
    public var points: [SpectrumPoint]
    public var parameters: [Parameter]
    public var warnings: [SpectrumWarning]

    public init(title: String, origin: String, owner: String, sourceURL: URL?,
                xUnit: XUnit, yUnit: YUnit, dataForm: DataForm,
                points: [SpectrumPoint], parameters: [Parameter],
                warnings: [SpectrumWarning]) {
        self.title = title; self.origin = origin; self.owner = owner
        self.sourceURL = sourceURL; self.xUnit = xUnit; self.yUnit = yUnit
        self.dataForm = dataForm; self.points = points
        self.parameters = parameters; self.warnings = warnings
    }

    public var xRange: ClosedRange<Double>? {
        guard let lo = points.map(\.x).min(), let hi = points.map(\.x).max() else { return nil }
        return lo...hi
    }
    public var yRange: ClosedRange<Double>? {
        guard let lo = points.map(\.y).min(), let hi = points.map(\.y).max() else { return nil }
        return lo...hi
    }
}
