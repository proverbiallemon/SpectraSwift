import Foundation
import Testing
@testable import SpectraKit

private func spec(_ ys: [Double], form: DataForm = .continuous) -> Spectrum {
    Spectrum(title: "T", origin: "", owner: "", sourceURL: nil,
             xUnit: .wavenumber, yUnit: .absorbance, dataForm: form,
             points: ys.enumerated().map { SpectrumPoint(x: Double($0.0), y: $0.1) },
             parameters: [], warnings: [])
}

@Test func quadraticSurvivesOrder2SmoothingInInterior() throws {
    let ys = (0..<40).map { let x = Double($0); return 2*x*x - 3*x + 1 }
    let out = try Smooth.savitzkyGolay(spec(ys), window: 7, polyOrder: 2)
    for i in 3..<37 {   // interior only; mirror-padded edges are approximate
        #expect(abs(out.points[i].y - ys[i]) < 1e-9)
    }
}

@Test func impulseYieldsKnownWindow5Order2Kernel() throws {
    var ys = [Double](repeating: 0, count: 21); ys[10] = 1
    let out = try Smooth.savitzkyGolay(spec(ys), window: 5, polyOrder: 2)
    let kernel = [-3.0, 12, 17, 12, -3].map { $0 / 35 }
    for (k, expected) in kernel.enumerated() {
        #expect(abs(out.points[8 + k].y - expected) < 1e-12)
    }
}

@Test func smoothingReducesNoise() throws {
    var seed: UInt64 = 42
    func noise() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.2
    }
    let clean = (0..<200).map { Foundation.sin(Double($0) * 0.1) }
    let noisy = clean.map { $0 + noise() }
    let out = try Smooth.savitzkyGolay(spec(noisy), window: 11, polyOrder: 3)
    func rms(_ a: [Double], _ b: [Double]) -> Double {
        let diffs = zip(a, b).map { ($0 - $1) * ($0 - $1) }
        let sumSq = diffs.reduce(0, +)
        return Foundation.sqrt(sumSq / Double(a.count))
    }
    let smoothedY = out.points.map(\.y)
    let rmsSmoothed = rms(smoothedY, clean)
    let rmsNoisy = rms(noisy, clean)
    #expect(rmsSmoothed < rmsNoisy)
}

@Test func derivedSpectrumIsSelfDocumenting() throws {
    let input = spec([1,2,3,4,5,6,7])
    let out = try Smooth.savitzkyGolay(input, window: 5, polyOrder: 2)
    #expect(out.title == "T (smoothed)")
    #expect(out.sourceURL == nil)
    #expect(out.parameters.contains { $0.key == "SMOOTHING" && $0.value.contains("window 5") })
    #expect(out.id != input.id)   // fresh identity via the memberwise init, not a struct copy
}

@Test func guardrails() {
    #expect(throws: SmoothError.tooFewPoints(needed: 11, have: 7)) {
        _ = try Smooth.savitzkyGolay(spec([1,2,3,4,5,6,7]), window: 11, polyOrder: 2)
    }
    #expect(throws: SmoothError.stickData) {
        _ = try Smooth.savitzkyGolay(spec([1,2,3,4,5,6,7], form: .peaks), window: 5, polyOrder: 2)
    }
    #expect(throws: SmoothError.invalidParameters("window must be odd, between 5 and 25")) {
        _ = try Smooth.savitzkyGolay(spec([1,2,3,4,5,6,7]), window: 6, polyOrder: 2)
    }
}

@Test func unsortedInputSmoothsIdenticallyToSorted() throws {
    let ys = (0..<30).map { Foundation.sin(Double($0) * 0.3) }
    let sorted = try Smooth.savitzkyGolay(spec(ys), window: 7, polyOrder: 2)
    var reversedSpec = spec(ys)
    reversedSpec.points = reversedSpec.points.reversed()
    let fromReversed = try Smooth.savitzkyGolay(reversedSpec, window: 7, polyOrder: 2)
    #expect(sorted.points == fromReversed.points)
}
