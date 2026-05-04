//  UpdateChecking.swift
//  Equaliser
//
//  Protocol for checking app updates against GitHub releases.

import Foundation

/// Protocol for checking app updates.
@MainActor
protocol UpdateChecking: ObservableObject {
    /// Whether an update is available.
    var updateAvailable: Bool { get }

    /// The latest version string from GitHub, if an update was found.
    var latestVersion: String? { get }

    /// Whether the update alert should be shown.
    /// Separate from `updateAvailable` so the user can dismiss the alert
    /// without re-triggering it in the same session.
    var showUpdateAlert: Bool { get set }

    /// Checks for updates against the GitHub releases API.
    /// Results are published via `updateAvailable` and `showUpdateAlert`.
    func checkForUpdates()
}
