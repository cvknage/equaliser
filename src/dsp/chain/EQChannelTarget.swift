/// Target for EQ coefficient staging.
/// Determines which channel(s) receive coefficient updates.
enum EQChannelTarget {
    /// Left channel only.
    case left

    /// Right channel only.
    case right

    /// Both channels (used in linked mode).
    case both
}