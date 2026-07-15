// App/UpdaterService.swift
import Foundation
import Combine
import Sparkle

/// Wraps Sparkle's standard updater. Sparkle handles the check UI,
/// download, EdDSA verification, install, and relaunch.
@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    private let updaterController: SPUStandardUpdaterController

    var updater: SPUUpdater { updaterController.updater }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

/// Publishes canCheckForUpdates so the menu item can disable itself
/// while a check is in flight (the pattern from Sparkle's SwiftUI docs).
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
