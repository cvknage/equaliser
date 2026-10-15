// DriverNameFormat.swift
// User-configurable name for the virtual device in automatic mode

import Foundation

/// A name template made of literal text and tokens, stored as e.g. `"{device} (Equaliser)"`.
struct DriverNameFormat: Equatable, Sendable {
    enum Token: String, CaseIterable, Sendable {
        case device
        case preset
        case eqState = "eq-state"

        var displayName: String {
            switch self {
            case .device: "Device"
            case .preset: "Preset"
            case .eqState: "EQ State"
            }
        }
    }

    enum Segment: Equatable, Sendable {
        case text(String)
        case token(Token)

        /// Length in the token field's editor: one character per token, UTF-16 for text.
        var editorLength: Int {
            switch self {
            case .text(let text): text.utf16.count
            case .token: 1
            }
        }
    }

    /// Values substituted for tokens.
    struct Values: Equatable, Sendable {
        var device: String
        /// `nil` when the EQ does not match a saved preset.
        var preset: String?
        var eqEnabled: Bool
    }

    /// Matches the original naming: "Speakers (Equaliser)".
    static let `default` = DriverNameFormat(segments: [.token(.device), .text(" (Equaliser)")])

    /// Used when a format renders to an empty name.
    static let fallbackName = "Equaliser"

    private(set) var segments: [Segment]

    init(segments: [Segment]) {
        self.segments = Self.normalized(segments)
    }

    /// Parses a stored format. Unknown `{names}` are kept as literal text.
    init(string: String) {
        var segments: [Segment] = []
        var rest = Substring(string)
        while let open = rest.firstIndex(of: "{") {
            segments.append(.text(String(rest[..<open])))
            guard let close = rest[open...].firstIndex(of: "}") else {
                rest = rest[open...]
                break
            }
            let name = String(rest[rest.index(after: open)..<close])
            if let token = Token(rawValue: name) {
                segments.append(.token(token))
            } else {
                segments.append(.text("{\(name)}"))
            }
            rest = rest[rest.index(after: close)...]
        }
        segments.append(.text(String(rest)))
        self.init(segments: segments)
    }

    /// The stored form, e.g. `"{device} (Equaliser)"`.
    var string: String {
        segments.map { segment in
            switch segment {
            case .text(let text): text
            case .token(let token): "{\(token.rawValue)}"
            }
        }.joined()
    }

    /// Whether the name changes with the preset or EQ state, not just the output device.
    var usesEQTokens: Bool {
        segments.contains { $0 == .token(.preset) || $0 == .token(.eqState) }
    }

    /// Builds the device name. Runs of whitespace collapse so an empty value leaves no gap.
    func render(_ values: Values) -> String {
        let raw = segments.map { segment in
            switch segment {
            case .text(let text): text
            case .token(.device): values.device
            case .token(.preset): values.preset ?? "Custom"
            case .token(.eqState): values.eqEnabled ? "On" : "Off"
            }
        }.joined()
        let name = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return name.isEmpty ? Self.fallbackName : name
    }

    /// Length in the token field's editor, where a token is one character and text is UTF-16.
    var editorLength: Int {
        segments.reduce(0) { $0 + $1.editorLength }
    }

    /// Replaces `range` (in editor units, see `editorLength`) with `segment`.
    func replacing(_ range: Range<Int>, with segment: Segment) -> DriverNameFormat {
        var before: [Segment] = []
        var after: [Segment] = []
        var start = 0
        for existing in segments {
            let length = existing.editorLength
            switch existing {
            case .token:
                if start + length <= range.lowerBound {
                    before.append(existing)
                } else if start >= range.upperBound {
                    after.append(existing)
                }
            case .text(let text):
                let units = Array(text.utf16)
                let head = min(max(range.lowerBound - start, 0), length)
                let tail = min(max(range.upperBound - start, 0), length)
                before.append(.text(String(decoding: units[..<head], as: UTF16.self)))
                after.append(.text(String(decoding: units[tail...], as: UTF16.self)))
            }
            start += length
        }
        return DriverNameFormat(segments: before + [segment] + after)
    }

    /// Merges adjacent text and drops empty text.
    private static func normalized(_ segments: [Segment]) -> [Segment] {
        var result: [Segment] = []
        for segment in segments {
            if case .text(let text) = segment {
                guard !text.isEmpty else { continue }
                if case .text(let previous) = result.last {
                    result[result.count - 1] = .text(previous + text)
                    continue
                }
            }
            result.append(segment)
        }
        return result
    }
}
