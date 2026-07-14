// App/SubtractSheetView.swift
import SwiftUI
import SpectraKit

struct SubtractSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var aID: UUID?
    @State private var bID: UUID?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtract Spectra").font(.headline)
            Picker("A:", selection: $aID) {
                ForEach(appState.spectra) { s in
                    Text(s.spectrum.title).tag(Optional(s.id))
                }
            }
            Picker("B (subtracted from A):", selection: $bID) {
                ForEach(appState.spectra) { s in
                    Text(s.spectrum.title).tag(Optional(s.id))
                }
            }
            if let errorText {
                Text(errorText).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Subtract") { subtract() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(aID == nil || bID == nil || aID == bID)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            aID = appState.selectionID ?? appState.spectra.first?.id
            bID = appState.spectra.first { $0.id != aID }?.id
        }
    }

    private func subtract() {
        guard let a = appState.spectra.first(where: { $0.id == aID }),
              let b = appState.spectra.first(where: { $0.id == bID }) else { return }
        do {
            let d = try Measure.subtract(a.spectrum, minus: b.spectrum)
            appState.addDerived(d)
            dismiss()
        } catch MeasureError.unitMismatch {
            errorText = "These spectra use different x-axis units, so subtracting them isn't meaningful."
        } catch MeasureError.noOverlap {
            errorText = "These spectra don't overlap on the x-axis, so there's nothing to subtract."
        } catch {
            errorText = error.localizedDescription
        }
    }
}
