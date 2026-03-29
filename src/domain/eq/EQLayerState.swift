/// State for a single EQ layer (e.g. user EQ, headphone correction, genre).
///
/// Each layer contains its own band configuration and bypass state.
/// Layers are processed in series within a channel.
/// This is a pure value type — safe to copy between threads.
struct EQLayerState: Codable, Sendable {
    /// Human-readable label for this layer (e.g. "User EQ", "Headphone Correction").
    var label: String

    /// Band configurations for this layer.
    /// Always sized to `EQConfiguration.maxBandCount` for pre-allocation.
    var bands: [EQBandConfiguration]

    /// Number of active bands in this layer (may be less than bands.count).
    var activeBandCount: Int

    /// Whether this entire layer is bypassed.
    var bypass: Bool

    /// Creates a default user EQ layer with the specified number of bands.
    /// - Parameter bandCount: Number of active bands (default from EQConfiguration).
    /// - Returns: A new EQLayerState configured as user EQ.
    static func userEQ(bandCount: Int = EQConfiguration.defaultBandCount) -> EQLayerState {
        EQLayerState(
            label: "User EQ",
            bands: EQConfiguration.defaultBands(),
            activeBandCount: bandCount,
            bypass: false
        )
    }

    /// Creates an empty layer (passthrough, no bands).
    /// - Parameter label: Optional label for the layer.
    /// - Returns: A new EQLayerState with no active bands.
    static func passthrough(label: String = "") -> EQLayerState {
        EQLayerState(
            label: label,
            bands: EQConfiguration.defaultBands(),
            activeBandCount: 0,
            bypass: false
        )
    }
}