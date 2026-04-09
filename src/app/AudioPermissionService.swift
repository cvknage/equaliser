// AudioPermissionService.swift
// Concrete implementation of PermissionRequesting using AVFoundation

import AVFoundation

/// Concrete implementation of PermissionRequesting using AVAudioApplication.
@MainActor
final class AudioPermissionService: PermissionRequesting {

    var isMicPermissionGranted: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}