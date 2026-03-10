import AppKit
import QuartzCore

/// GPU-accelerated peak meter view using Core Animation layers.
/// Implements MeterObserver for direct updates from MeterStore, bypassing SwiftUI.
final class PeakMeterLayer: NSView, MeterObserver {
    // MARK: - Sublayers

    private let backgroundLayer = CALayer()
    private let fillLayer = CAGradientLayer()
    private let fillMaskLayer = CALayer()
    private let peakHoldLayer = CALayer()
    private let clipLayer = CALayer()
    private let clipTextLayer = CATextLayer()
    private let borderLayer = CAShapeLayer()

    // MARK: - Gradient Colors (matching current SwiftUI meters)

    private let gradientColors: [CGColor] = [
        NSColor(red: 0.0, green: 0.45, blue: 0.95, alpha: 1.0).cgColor,  // Blue
        NSColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0).cgColor,   // Green
        NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0).cgColor,   // Yellow
        NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0).cgColor,   // Red
    ]

    private let gradientLocations: [NSNumber] = [0.0, 0.3, 0.6, 1.0]

    // MARK: - State

    private var currentPeak: Float = 0
    private var currentPeakHold: Float = 0
    private var isCurrentlyClipping: Bool = false
    private var isSetupComplete = false

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    // MARK: - Setup

    private func setupLayers() {
        wantsLayer = true
        guard let layer = self.layer else { return }

        // Background layer (gray rounded rect)
        backgroundLayer.backgroundColor = NSColor.gray.withAlphaComponent(0.18).cgColor
        backgroundLayer.cornerRadius = 4
        backgroundLayer.masksToBounds = true
        layer.addSublayer(backgroundLayer)

        // Fill gradient layer
        fillLayer.colors = gradientColors
        fillLayer.locations = gradientLocations
        fillLayer.startPoint = CGPoint(x: 0.5, y: 0)  // bottom (y=0 in CALayer is bottom)
        fillLayer.endPoint = CGPoint(x: 0.5, y: 1)    // top (y=1 in CALayer is top)
        fillLayer.cornerRadius = 3
        
        // Fill mask - use a solid color layer that we scale via transform
        fillMaskLayer.backgroundColor = NSColor.white.cgColor
        fillMaskLayer.anchorPoint = CGPoint(x: 0.5, y: 0)  // Anchor at bottom center
        fillLayer.mask = fillMaskLayer
        layer.addSublayer(fillLayer)

        // Peak hold line (white, 2pt height)
        peakHoldLayer.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        peakHoldLayer.cornerRadius = 1
        layer.addSublayer(peakHoldLayer)

        // Clip indicator (red badge)
        clipLayer.backgroundColor = NSColor.red.cgColor
        clipLayer.cornerRadius = 2
        clipLayer.isHidden = true

        clipTextLayer.string = "CLIP"
        clipTextLayer.fontSize = 6
        clipTextLayer.font = NSFont.systemFont(ofSize: 6, weight: .bold)
        clipTextLayer.foregroundColor = NSColor.white.cgColor
        clipTextLayer.alignmentMode = .center
        clipTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        clipLayer.addSublayer(clipTextLayer)

        layer.addSublayer(clipLayer)

        // Border layer
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.gray.withAlphaComponent(0.4).cgColor
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)
        
        isSetupComplete = true
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let bounds = self.bounds
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Background fills entire bounds
        backgroundLayer.frame = bounds

        // Fill layer fills entire bounds
        fillLayer.frame = bounds
        
        // Fill mask layer - set to full size, we'll scale it
        fillMaskLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)

        // Peak hold line (width of meter, 2pt height)
        peakHoldLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 2)

        // Clip indicator (positioned at top, small badge)
        let clipWidth: CGFloat = 16
        let clipHeight: CGFloat = 10
        clipLayer.frame = CGRect(
            x: (bounds.width - clipWidth) / 2,
            y: bounds.height - clipHeight - 2,
            width: clipWidth,
            height: clipHeight
        )
        clipTextLayer.frame = clipLayer.bounds

        // Border path
        let borderPath = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4, cornerHeight: 4, transform: nil)
        borderLayer.path = borderPath
        borderLayer.frame = bounds
        
        // Re-apply current state
        updateFillTransform()
        updatePeakHoldPosition()
        
        CATransaction.commit()
    }

    // MARK: - MeterObserver Protocol

    func meterUpdated(value: Float, hold: Float, clipping: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        currentPeak = max(0, min(1, value))
        currentPeakHold = max(0, min(1, hold))
        isCurrentlyClipping = clipping

        updateFillTransform()
        updatePeakHoldPosition()
        updateClipIndicator()

        CATransaction.commit()
    }

    // MARK: - Private Updates

    private func updateFillTransform() {
        guard isSetupComplete else { return }
        
        let scale = CGFloat(currentPeak)
        
        // Scale from bottom: scale Y, no translation needed because anchor is at bottom
        fillMaskLayer.transform = CATransform3DMakeScale(1.0, scale, 1.0)
    }

    private func updatePeakHoldPosition() {
        guard isSetupComplete else { return }
        
        guard currentPeakHold > 0 else {
            peakHoldLayer.isHidden = true
            return
        }

        peakHoldLayer.isHidden = false

        let bounds = self.bounds
        let holdY = bounds.height * CGFloat(currentPeakHold)
        var frame = peakHoldLayer.frame
        frame.origin.y = holdY - 1  // Center the 2pt line on the hold position
        peakHoldLayer.frame = frame
    }

    private func updateClipIndicator() {
        clipLayer.isHidden = !isCurrentlyClipping
    }
}
