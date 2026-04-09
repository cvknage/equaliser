import AppKit
import QuartzCore

/// GPU-accelerated RMS meter view using Core Animation layers.
/// Implements MeterObserver for direct updates from MeterStore, bypassing SwiftUI.
final class RMSMeterLayer: NSView, MeterObserver {
    // MARK: - Sublayers

    private let backgroundLayer = CALayer()
    private let fillLayer = CAGradientLayer()
    private let fillMaskLayer = CALayer()
    private let borderLayer = CAShapeLayer()

    // MARK: - Gradient Colors (matching current SwiftUI RMS meters)

    private let gradientColors: [CGColor] = [
        NSColor(red: 0.0, green: 0.35, blue: 0.4, alpha: 1.0).cgColor,   // Dark teal
        NSColor(red: 0.0, green: 0.5, blue: 0.5, alpha: 1.0).cgColor,   // Teal
        NSColor(red: 0.5, green: 0.6, blue: 0.2, alpha: 1.0).cgColor,   // Yellow-green
        NSColor(red: 0.6, green: 0.2, blue: 0.2, alpha: 1.0).cgColor,   // Red-brown
    ]

    private let gradientLocations: [NSNumber] = [0.0, 0.3, 0.6, 1.0]

    // MARK: - State

    private var currentRMS: Float = 0
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

        // Reset transform before frame calculations to avoid interaction issues
        fillMaskLayer.transform = CATransform3DIdentity

        // Background fills entire bounds
        backgroundLayer.frame = bounds

        // Fill layer fills entire bounds
        fillLayer.frame = bounds
        
        // Fill mask layer - use bounds + position with explicit anchor point
        // This prevents issues when appearance changes trigger re-layout
        fillMaskLayer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        fillMaskLayer.position = CGPoint(x: bounds.midX, y: 0)

        // Border path
        let borderPath = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4, cornerHeight: 4, transform: nil)
        borderLayer.path = borderPath
        borderLayer.frame = bounds
        
        // Re-apply current state - must be done after all frame/bounds operations
        updateFillTransform()
        
        CATransaction.commit()
    }

    // MARK: - MeterObserver Protocol

    func meterUpdated(value: Float, hold: Float, clipping: Bool) {
        currentRMS = max(0, min(1, value))
        updateFillTransform()
    }

    // MARK: - Private Updates

    private func updateFillTransform() {
        guard isSetupComplete else { return }
        
        let scale = CGFloat(currentRMS)
        
        // Scale from bottom: scale Y, no translation needed because anchor is at bottom
        fillMaskLayer.transform = CATransform3DMakeScale(1.0, scale, 1.0)
    }
}
