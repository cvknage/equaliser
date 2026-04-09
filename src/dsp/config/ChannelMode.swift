/// How audio channels are processed — determines whether one or two EQ chains are active.
enum ChannelMode: String, Codable, Sendable, CaseIterable {
    /// One configuration applied to both L and R channels.
    case linked

    /// Independent L and R configurations.
    case stereo
}