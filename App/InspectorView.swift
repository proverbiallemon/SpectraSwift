// App/InspectorView.swift
import SwiftUI
import SpectraKit

struct InspectorView: View {
    @Environment(AppState.self) private var appState
    @State private var filter = ""

    var body: some View {
        if let item = appState.selected {
            let params = item.spectrum.parameters.filter {
                filter.isEmpty
                    || $0.key.localizedCaseInsensitiveContains(filter)
                    || $0.value.localizedCaseInsensitiveContains(filter)
            }
            VStack(spacing: 0) {
                TextField("Filter parameters", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                List {
                    if !item.spectrum.warnings.isEmpty {
                        Section("Warnings") {
                            ForEach(item.spectrum.warnings, id: \.message) { w in
                                Label(w.message, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Section("Parameters") {
                        ForEach(params) { p in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.key)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(p.value)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                description: Text("Select a spectrum to see its parameters."))
        }
    }
}
