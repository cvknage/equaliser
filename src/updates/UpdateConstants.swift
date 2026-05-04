//  UpdateConstants.swift
//  Equaliser
//
//  Constants for app update checking.

import Foundation

/// GitHub API endpoint for the latest release.
let UPDATE_CHECK_API_URL = "https://api.github.com/repos/cvknage/equaliser/releases/latest"

/// Download page for users.
let UPDATE_DOWNLOAD_URL = "https://equaliser.knage.net"

/// HTTP timeout interval for the update check request (seconds).
let UPDATE_CHECK_TIMEOUT_INTERVAL: TimeInterval = 15
