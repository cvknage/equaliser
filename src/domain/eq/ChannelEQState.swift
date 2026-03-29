/// Per-channel EQ state containing one or more layers.
///
/// Layers are processed in series (index 0 first).
/// This is a pure value type — safe to copy between threads.
struct ChannelEQState: Codable, Sendable {
    /// Ordered list of EQ layers. Processed in series (index 0 first).
    /// Currently contains exactly one layer (User EQ).
    /// Future: headphone correction, genre presets, etc.
    var layers: [EQLayerState]

    /// Convenience: the primary user EQ layer (always index 0).
    var userEQ: EQLayerState {
        get { layers[0] }
        set { layers[0] = newValue }
    }

    /// Creates a default channel state with the specified number of bands.
    /// - Parameter bandCount: Number of active bands (default from EQConfiguration).
    /// - Returns: A new ChannelEQState with a single user EQ layer.
    static func `default`(bandCount: Int = EQConfiguration.defaultBandCount) -> ChannelEQState {
        ChannelEQState(layers: [.userEQ(bandCount: bandCount)])
    }

    /// Creates a channel state from an existing layer.
    /// - Parameter layer: The layer to use (becomes layer 0).
    /// - Returns: A new ChannelEQState with the given layer.
    static func from(layer: EQLayerState) -> ChannelEQState {
        ChannelEQState(layers: [layer])
    }
}