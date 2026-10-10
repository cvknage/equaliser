// OutputPresetKey.swift
// Stable storage key for output-device preset assignments

import Foundation

/// Maps a CoreAudio device UID to the key its preset assignment is stored under.
enum OutputPresetKey {
    private static let usbPrefix = "AppleUSBAudioEngine"
    private static let hexDigits = Set("0123456789abcdef")

    /// USB devices without a serial number get UIDs like
    /// `AppleUSBAudioEngine:<vendor>:<product>:<locationID>:<interface>`, where the
    /// location ID (`%x`) changes with the port or hub. Blanking it keeps one
    /// assignment per device. Other UIDs are unchanged, and the result is idempotent.
    static func make(for uid: String) -> String {
        var fields = uid.split(separator: ":", omittingEmptySubsequences: false)
        // Index from the end because vendor and product names may contain colons.
        guard fields.count >= 5, fields[0] == usbPrefix else { return uid }
        let location = fields[fields.count - 2]
        guard isLocationID(location) else { return uid }
        fields[fields.count - 2] = ""
        return fields.joined(separator: ":")
    }

    private static func isLocationID(_ field: Substring) -> Bool {
        (1...8).contains(field.count) && field.first != "0" && field.allSatisfy(hexDigits.contains)
    }
}
