import SwiftUI

/// Shared constants for meter visualization.
enum MeterConstants {
    static let meterRange: ClosedRange<Float> = -36...0
    static let gamma: Float = 0.5
    static let meterHeight: CGFloat = 126
    static let standardTickValues: [Float] = [0, -6, -12, -18, -24, -30, -36]

    /// Converts a dB value to a normalized position (0-1) matching the meter visual.
    static func normalizedPosition(for db: Float) -> Float {
        if db <= meterRange.lowerBound { return 0 }
        if db >= meterRange.upperBound { return 1 }
        let amp = powf(10.0, 0.05 * db)
        let minAmp = powf(10.0, 0.05 * meterRange.lowerBound)
        let maxAmp = powf(10.0, 0.05 * meterRange.upperBound)
        let normalizedAmp = (amp - minAmp) / (maxAmp - minAmp)
        return powf(normalizedAmp, gamma)
    }
}

struct MeterScaleView: View {
    let height: CGFloat

    var body: some View {
        // Match PeakMeter structure: VStack(spacing: 4) with content + label
        VStack(spacing: 4) {
            Canvas { context, size in
                for db in MeterConstants.standardTickValues {
                    let position = MeterConstants.normalizedPosition(for: db)
                    let y = size.height * (1 - CGFloat(position))

                    // Draw tick mark
                    let tickWidth: CGFloat = db == 0 ? 6 : 4
                    let tickRect = CGRect(
                        x: size.width - tickWidth,
                        y: y - 0.5,
                        width: tickWidth,
                        height: 1
                    )
                    context.fill(Path(tickRect), with: .color(.gray.opacity(0.6)))

                    // Draw label with appropriate anchor to avoid clipping
                    let label = db == 0 ? "0" : String(format: "%.0f", db)
                    let text = Text(label)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    // Use different anchors for top/bottom to keep text in bounds
                    let anchor: UnitPoint
                    if db == 0 {
                        anchor = .topTrailing  // Top label: text below tick
                    } else if db == -36 {
                        anchor = .bottomTrailing  // Bottom label: text above tick
                    } else {
                        anchor = .trailing  // Middle labels: centered on tick
                    }

                    context.draw(
                        context.resolve(text),
                        at: CGPoint(x: size.width - tickWidth - 3, y: y),
                        anchor: anchor
                    )
                }
            }
            .frame(width: 32, height: height)

            // Match channel label height from PeakMeter
            Text(" ")
                .font(.caption2)
                .foregroundStyle(.clear)
        }
    }
}
