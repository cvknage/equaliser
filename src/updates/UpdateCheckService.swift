//  UpdateCheckService.swift
//  Equaliser
//
//  Service that checks for app updates via the GitHub releases API.

import Foundation
import OSLog

/// Service that checks for app updates via the GitHub releases API.
@MainActor
final class UpdateCheckService: ObservableObject, UpdateChecking {

    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    @Published var showUpdateAlert: Bool = false
    @Published var isChecking: Bool = false

    private let logger = Logger(subsystem: "net.knage.equaliser", category: "UpdateCheckService")

    // MARK: - Update Checking

    func checkForUpdates() {
        guard !isChecking else { return }
        guard !updateAvailable else { return }

        isChecking = true

        Task { [weak self] in
            guard let self else { return }

            let result = await Self.performUpdateCheck()

            switch result {
            case .upToDate:
                self.logger.info("App is up to date")
                self.updateAvailable = false
                self.latestVersion = nil

            case .updateAvailable(let version):
                self.logger.info("Update available: \(version)")
                self.latestVersion = version
                self.updateAvailable = true
                self.showUpdateAlert = true

            case .error(let error):
                self.logger.debug("Update check failed (silent): \(String(describing: error))")
            }

            self.isChecking = false
        }
    }

    // MARK: - Network Request (nonisolated)

    private nonisolated static func performUpdateCheck() async -> UpdateCheckResult {
        guard let url = URL(string: UPDATE_CHECK_API_URL) else {
            return .error(.invalidResponse)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = UPDATE_CHECK_TIMEOUT_INTERVAL
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            return .error(.networkUnavailable)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return .error(.invalidResponse)
        }

        return parseReleaseResponse(data)
    }

    // MARK: - Parsing (pure)

    nonisolated static func parseReleaseResponse(_ data: Data) -> UpdateCheckResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            return .error(.parsingFailed)
        }

        let latestVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let currentVersion = currentAppVersion()

        guard !latestVersion.isEmpty, !currentVersion.isEmpty else {
            return .error(.parsingFailed)
        }

        if isVersion(latestVersion, newerThan: currentVersion) {
            return .updateAvailable(latestVersion: latestVersion)
        } else {
            return .upToDate
        }
    }

    // MARK: - Version Comparison (pure)

    nonisolated static func currentAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    nonisolated static func isVersion(_ version: String, newerThan other: String) -> Bool {
        let versionComponents = version.split(separator: ".").compactMap { Int($0) }
        let otherComponents = other.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(versionComponents.count, otherComponents.count)
        let paddedVersion = versionComponents + Array(repeating: 0, count: maxCount - versionComponents.count)
        let paddedOther = otherComponents + Array(repeating: 0, count: maxCount - otherComponents.count)

        for (v, o) in zip(paddedVersion, paddedOther) {
            if v > o { return true }
            if v < o { return false }
        }
        return false
    }
}
