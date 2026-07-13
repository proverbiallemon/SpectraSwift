// App/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        List(selection: $state.selectionID) {
            ForEach(appState.spectra) { item in
                @Bindable var item = item
                HStack(spacing: 8) {
                    Toggle("", isOn: $item.isVisible)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                    ColorPicker("", selection: $item.color, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.spectrum.title)
                            .lineLimit(1)
                        Text(item.spectrum.sourceURL?.lastPathComponent ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !item.spectrum.warnings.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .help(item.spectrum.warnings.map(\.message)
                                .joined(separator: "\n"))
                    }
                }
                .tag(item.id)
                .contextMenu {
                    Button("Remove", role: .destructive) {
                        appState.remove(item.id)
                    }
                }
            }
        }
    }
}
