// PermissionRequesting.swift
// Protocol for audio permission checking and requesting

import AVFoundation

/// Protocol for checking and requesting microphone permission.
/// Abstracts AVAudioApplication to enable testing of permission flows.
@MainActor
protocol PermissionRequesting {
    /// Whether microphone permission has been granted.
    var isMicPermissionGranted: Bool { get }

    /// Requests microphone permission from the user.
    /// Returns true if granted, false if denied.
    func requestMicPermission() async -> Bool
}