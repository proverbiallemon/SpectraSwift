import Foundation

public enum CSVExporter {
    public static func export(_ s: Spectrum) -> String {
        var out = "\(s.xUnit.label),\(s.yUnit.label)\n"
        for p in s.points {
            out += "\(format(p.x)),\(format(p.y))\n"
        }
        return out
    }
    static func format(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15
            ? String(Int(v)) : String(v)
    }
}

public enum JCAMPExporter {
    /// Simple uncompressed (XY..XY) JCAMP-DX 4.24 output.
    public static func export(_ s: Spectrum) -> String {
        let xu: String = switch s.xUnit {
        case .wavenumber: "1/CM"
        case .wavelengthNm: "NANOMETERS"
        case .wavelengthUm: "MICROMETERS"
        case .massCharge: "M/Z"
        case .seconds: "SECONDS"
        case .other(let o): o
        }
        let yu: String = switch s.yUnit {
        case .transmittance: "TRANSMITTANCE"
        case .absorbance: "ABSORBANCE"
        case .relativeIntensity: "RELATIVE INTENSITY"
        case .other(let o): o
        }
        let dataType = s.parameters.first {
            $0.key.uppercased().replacingOccurrences(of: " ", with: "") == "DATATYPE"
        }?.value ?? (s.dataForm == .peaks ? "MASS SPECTRUM" : "SPECTRUM")
        var out = """
        ##TITLE=\(s.title)
        ##JCAMP-DX=4.24
        ##DATA TYPE=\(dataType)
        ##ORIGIN=\(s.origin)
        ##OWNER=\(s.owner)
        ##XUNITS=\(xu)
        ##YUNITS=\(yu)
        ##XFACTOR=1
        ##YFACTOR=1
        ##NPOINTS=\(s.points.count)
        """
        if let xr = s.xRange {
            out += "\n##FIRSTX=\(xr.lowerBound)\n##LASTX=\(xr.upperBound)"
        }
        out += s.dataForm == .peaks
            ? "\n##PEAK TABLE=(XY..XY)" : "\n##XYPOINTS=(XY..XY)"
        for p in s.points {
            out += "\n\(CSVExporter.format(p.x)),\(CSVExporter.format(p.y))"
        }
        out += "\n##END=\n"
        return out
    }
}
