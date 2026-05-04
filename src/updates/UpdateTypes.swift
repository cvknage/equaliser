//  UpdateTypes.swift
//  Equaliser
//
//  Pure types for app update checking.

import Foundation

/// Result of checking for app updates.
enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case updateAvailable(latestVersion: String)
    case error(UpdateCheckError)
}

/// Errors that can occur during update checking.
enum UpdateCheckError: Error, Equatable, Sendable {
    case networkUnavailable
    case invalidResponse
    case parsingFailed
}
