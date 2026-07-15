import Foundation

public enum SpectrumFileError: Error, Equatable {
    case unrecognizedFormat
    case unreadable(String)
}

public enum SpectrumFile {
    static let opusMagic: [UInt8] = [0x0A, 0x0A, 0xFE, 0xFE]

    public static func read(url: URL) throws -> [Spectrum] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw SpectrumFileError.unreadable(error.localizedDescription) }
        return try read(data: data, sourceURL: url)
    }

    public static func read(data: Data, sourceURL: URL?) throws -> [Spectrum] {
        if data.count >= 4, Array(data.prefix(4)) == opusMagic {
            return try OPUSReader.read(data: data, sourceURL: sourceURL)
        }
        // JCAMP: first non-blank content starts with ##TITLE (allow BOM/whitespace)
        if let head = String(data: data.prefix(512), encoding: .utf8)
            ?? String(data: data.prefix(512), encoding: .isoLatin1),
           head.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" }).hasPrefix("##TITLE") {
            return try JCAMPReader.read(data: data, sourceURL: sourceURL)
        }
        throw SpectrumFileError.unrecognizedFormat
    }
}
