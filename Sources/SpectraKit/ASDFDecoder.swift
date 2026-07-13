// Sources/SpectraKit/ASDFDecoder.swift
import Foundation

public enum ASDFError: Error, Equatable {
    case malformed(String)
}

public struct ASDFLine: Equatable {
    public var x: Double
    public var ys: [Double]
    /// True when the last value on the line was DIF- or DIF-DUP-encoded;
    /// the next line's first Y is then a checkpoint, not a new datum.
    public var endedInDIF: Bool
}

public enum ASDFDecoder {
    // Pseudo-digit tables (JCAMP-DX 4.24 §5)
    private static let sqz: [Character: (sign: Double, digit: Int)] = [
        "@": (1, 0), "A": (1, 1), "B": (1, 2), "C": (1, 3), "D": (1, 4),
        "E": (1, 5), "F": (1, 6), "G": (1, 7), "H": (1, 8), "I": (1, 9),
        "a": (-1, 1), "b": (-1, 2), "c": (-1, 3), "d": (-1, 4),
        "e": (-1, 5), "f": (-1, 6), "g": (-1, 7), "h": (-1, 8), "i": (-1, 9),
    ]
    private static let dif: [Character: (sign: Double, digit: Int)] = [
        "%": (1, 0), "J": (1, 1), "K": (1, 2), "L": (1, 3), "M": (1, 4),
        "N": (1, 5), "O": (1, 6), "P": (1, 7), "Q": (1, 8), "R": (1, 9),
        "j": (-1, 1), "k": (-1, 2), "l": (-1, 3), "m": (-1, 4),
        "n": (-1, 5), "o": (-1, 6), "p": (-1, 7), "q": (-1, 8), "r": (-1, 9),
    ]
    private static let dup: [Character: Int] = [
        "S": 1, "T": 2, "U": 3, "V": 4, "W": 5, "X": 6, "Y": 7, "Z": 8, "s": 9,
    ]

    private enum Mode { case affn, sqz, dif, dup }

    /// Decode one XYDATA line. `previousY` is the running Y from the prior
    /// line, needed because DIF checkpoints reference it.
    public static func decodeLine(_ line: String, previousY: Double?) throws -> ASDFLine {
        var tokens: [(mode: Mode, text: String)] = []
        var current = ""
        var currentMode: Mode? = nil

        func flush() {
            if let m = currentMode, !current.isEmpty { tokens.append((m, current)) }
            current = ""; currentMode = nil
        }

        for ch in line {
            if ch == " " || ch == "\t" || ch == "," || ch == ";" {
                flush(); continue
            }
            if let _ = sqz[ch] { flush(); currentMode = .sqz; current = String(ch); continue }
            if let _ = dif[ch] { flush(); currentMode = .dif; current = String(ch); continue }
            if let _ = dup[ch] { flush(); currentMode = .dup; current = String(ch); continue }
            if ch == "+" || ch == "-" {
                // sign starts a new AFFN/PAC token unless it follows E/e (exponent)
                if let last = current.last, last == "E" || last == "e", currentMode == .affn {
                    current.append(ch); continue
                }
                flush(); currentMode = .affn; current = String(ch); continue
            }
            if ch.isNumber || ch == "." || ch == "E" || ch == "e" {
                if currentMode == nil { currentMode = .affn }
                current.append(ch); continue
            }
            if ch == "?" { // JCAMP "invalid point" marker
                flush(); tokens.append((.affn, "?")); continue
            }
            throw ASDFError.malformed("Unexpected character '\(ch)' in data line")
        }
        flush()

        guard let first = tokens.first, first.mode == .affn, first.text != "?",
              let x = Double(first.text) else {
            throw ASDFError.malformed("Line does not start with a numeric X value: \(line.prefix(40))")
        }

        var ys: [Double] = []
        var lastY = previousY ?? 0
        var lastWasDIF = false
        var lastDelta = 0.0

        for tok in tokens.dropFirst() {
            switch tok.mode {
            case .affn:
                if tok.text == "?" { ys.append(.nan); lastWasDIF = false; continue }
                guard let v = Double(tok.text) else {
                    throw ASDFError.malformed("Bad number '\(tok.text)'")
                }
                ys.append(v); lastY = v; lastWasDIF = false
            case .sqz:
                let head = tok.text.first ?? "@"
                guard let (sign, digit) = sqz[head],
                      let v = Double(String(digit) + tok.text.dropFirst()) else {
                    throw ASDFError.malformed("Bad SQZ token '\(tok.text)'")
                }
                lastY = sign * v
                ys.append(lastY); lastWasDIF = false
            case .dif:
                let head = tok.text.first ?? "%"
                guard let (sign, digit) = dif[head],
                      let v = Double(String(digit) + tok.text.dropFirst()) else {
                    throw ASDFError.malformed("Bad DIF token '\(tok.text)'")
                }
                lastDelta = sign * v
                lastY += lastDelta
                ys.append(lastY); lastWasDIF = true
            case .dup:
                let head = tok.text.first ?? "S"
                guard let base = dup[head],
                      let count = Int(String(base) + tok.text.dropFirst()) else {
                    throw ASDFError.malformed("Bad DUP token '\(tok.text)'")
                }
                // DUP repeats the previous token (count-1) more times.
                guard !ys.isEmpty else {
                    throw ASDFError.malformed("DUP with no preceding value")
                }
                for _ in 0..<(count - 1) {
                    if lastWasDIF {
                        lastY += lastDelta
                        ys.append(lastY)
                    } else {
                        ys.append(lastY)
                    }
                }
            }
        }
        return ASDFLine(x: x, ys: ys, endedInDIF: lastWasDIF)
    }
}
