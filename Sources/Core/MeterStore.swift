import AppKit
import Combine
import Foundation
import os.log

/// Manages meter state and updates observers directly.
/// Uses Timer for meter updates at 30 FPS.
/// Updates are pushed directly to observers, bypassing SwiftUI's observation system.
@MainActor
final class MeterStore: ObservableObject {
    // MARK: - Observable Properties (for UI controls only)
    
    /// Whether meters are enabled. Published for UI toggle synchronization only.
    @Published var metersEnabled: Bool = true {
        didSet {
            if !metersEnabled {
                // Reset all observers to silent state
                notifyAllObserversSilent()
                stopMeterUpdates()
            } else {
                startMeterUpdates()
            }
        }
    }
    
    // MARK: - Observer Management
    
    private var observers: [MeterType: [WeakMeterObserver]] = [:]
    private let observerQueue = DispatchQueue(label: "net.knage.equaliser.meterObservers", qos: .userInteractive)
    
    // MARK: - Dependencies
    
    private weak var renderPipeline: RenderPipeline?
    private weak var equaliserWindow: NSWindow?
    
    // MARK: - Timing
    
    private var meterTimer: AnyCancellable?
    private static let meterInterval: TimeInterval = 1.0 / 30.0  // 30 FPS
    
    // MARK: - State
    
    private var metersAtRest = false
    private var lastMeterValues: [MeterType: MeterValues] = [:]
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "MeterStore")
    
    // MARK: - Constants
    
    private static let peakHoldHoldDuration: TimeInterval = 1.0
    private static let peakHoldDecayPerTick: Float = 0.02
    private static let peakAttackSmoothing: Float = 1.0
    private static let peakReleaseSmoothing: Float = 0.33
    private static let rmsSmoothing: Float = 0.12
    private static let clipHoldDuration: TimeInterval = 0.5
    private static let meterRange: ClosedRange<Float> = Float(-36)...Float(0)
    private static let gamma: Float = 0.5
    private static let changeThreshold: Float = 0.002
    private static let silenceThreshold: Float = -85
    private static let atRestThreshold: Float = 0.01
    
    // MARK: - Value Storage
    
    private struct MeterValues {
        var peak: Float = 0
        var peakHold: Float = 0
        var peakHoldTimeRemaining: TimeInterval = 0
        var clipHold: TimeInterval = 0
        var rms: Float = 0
    }
    
    // MARK: - Initialization
    
    init(metersEnabled: Bool = true) {
        self.metersEnabled = metersEnabled
    }
    
    // MARK: - Observer Registration
    
    func addObserver(_ observer: MeterObserver, for type: MeterType) {
        observerQueue.sync {
            if observers[type] == nil {
                observers[type] = []
            }
            // Remove dead observers and check if already registered
            observers[type]?.removeAll { $0.observer == nil || $0.observer === observer }
            observers[type]?.append(WeakMeterObserver(observer: observer))
        }
        
        // Send initial silent state if meters disabled
        if !metersEnabled {
            observer.meterUpdated(value: 0, hold: 0, clipping: false)
        }
    }
    
    func removeObserver(_ observer: MeterObserver, for type: MeterType) {
        observerQueue.sync {
            observers[type]?.removeAll { $0.observer == nil || $0.observer === observer }
        }
    }
    
    func removeAllObservers(for observer: MeterObserver) {
        observerQueue.sync {
            for type in MeterType.allCases {
                observers[type]?.removeAll { $0.observer == nil || $0.observer === observer }
            }
        }
    }
    
    // MARK: - Lifecycle
    
    func setRenderPipeline(_ pipeline: RenderPipeline?) {
        self.renderPipeline = pipeline
    }
    
    func setEqualiserWindow(_ window: NSWindow?) {
        // Remove observers from old window
        if let oldWindow = equaliserWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMiniaturizeNotification, object: oldWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didDeminiaturizeNotification, object: oldWindow)
        }
        
        self.equaliserWindow = window
        
        // Add observers to new window
        if let window = window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidMiniaturize),
                name: NSWindow.didMiniaturizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidDeminiaturize),
                name: NSWindow.didDeminiaturizeNotification,
                object: window
            )
        }
    }
    
    @objc private func windowDidMiniaturize() {
        windowBecameHidden()
    }
    
    @objc private func windowDidDeminiaturize() {
        windowBecameVisible()
    }
    
    func startMeterUpdates() {
        guard meterTimer == nil else { return }
        guard metersEnabled else { return }
        
        meterTimer = Timer.publish(every: Self.meterInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMeterSnapshot()
            }
    }
    
    func stopMeterUpdates() {
        meterTimer?.cancel()
        meterTimer = nil
        metersAtRest = false
        notifyAllObserversSilent()
    }
    
    // MARK: - Window Lifecycle
    
    func windowBecameVisible() {
        guard metersEnabled else { return }
        startMeterUpdates()
    }
    
    func windowBecameHidden() {
        stopMeterUpdates()
    }
    
    // MARK: - Update Cycle
    
    private func refreshMeterSnapshot() {
        guard metersEnabled else {
            notifyAllObserversSilent()
            return
        }
        
        // Check window visibility
        if let window = equaliserWindow {
            guard window.isVisible else { return }
        } else if let keyWindow = NSApp.keyWindow {
            guard keyWindow.isVisible else { return }
        }
        
        guard let pipeline = renderPipeline else { return }
        
        let snapshot = pipeline.currentMeters()
        
        // Check if at rest (all meters silent)
        if metersAtRest {
            let stillSilent = snapshot.inputDB.allSatisfy({ $0 <= Self.silenceThreshold }) &&
                              snapshot.outputDB.allSatisfy({ $0 <= Self.silenceThreshold }) &&
                              snapshot.inputRmsDB.allSatisfy({ $0 <= Self.silenceThreshold }) &&
                              snapshot.outputRmsDB.allSatisfy({ $0 <= Self.silenceThreshold })
            
            if stillSilent {
                return
            }
            metersAtRest = false
        }
        
        // Process each meter type
        let interval = Self.meterInterval
        
        // Input Peak - Left
        updateMeter(
            type: .inputPeakLeft,
            dbValue: snapshot.inputDB.indices.contains(0) ? snapshot.inputDB[0] : Self.meterRange.lowerBound,
            interval: interval
        )
        
        // Input Peak - Right
        updateMeter(
            type: .inputPeakRight,
            dbValue: snapshot.inputDB.indices.contains(1) ? snapshot.inputDB[1] : Self.meterRange.lowerBound,
            interval: interval
        )
        
        // Output Peak - Left
        updateMeter(
            type: .outputPeakLeft,
            dbValue: snapshot.outputDB.indices.contains(0) ? snapshot.outputDB[0] : Self.meterRange.lowerBound,
            interval: interval
        )
        
        // Output Peak - Right
        updateMeter(
            type: .outputPeakRight,
            dbValue: snapshot.outputDB.indices.contains(1) ? snapshot.outputDB[1] : Self.meterRange.lowerBound,
            interval: interval
        )
        
        // Input RMS - Left
        updateRMSMeter(
            type: .inputRMSLeft,
            dbValue: snapshot.inputRmsDB.indices.contains(0) ? snapshot.inputRmsDB[0] : Self.meterRange.lowerBound
        )
        
        // Input RMS - Right
        updateRMSMeter(
            type: .inputRMSRight,
            dbValue: snapshot.inputRmsDB.indices.contains(1) ? snapshot.inputRmsDB[1] : Self.meterRange.lowerBound
        )
        
        // Output RMS - Left
        updateRMSMeter(
            type: .outputRMSLeft,
            dbValue: snapshot.outputRmsDB.indices.contains(0) ? snapshot.outputRmsDB[0] : Self.meterRange.lowerBound
        )
        
        // Output RMS - Right
        updateRMSMeter(
            type: .outputRMSRight,
            dbValue: snapshot.outputRmsDB.indices.contains(1) ? snapshot.outputRmsDB[1] : Self.meterRange.lowerBound
        )
        
        // Check if we should go back to rest
        let inputPeakLeft = lastMeterValues[.inputPeakLeft]?.peak ?? Float(0)
        let inputPeakRight = lastMeterValues[.inputPeakRight]?.peak ?? Float(0)
        let outputPeakLeft = lastMeterValues[.outputPeakLeft]?.peak ?? Float(0)
        let outputPeakRight = lastMeterValues[.outputPeakRight]?.peak ?? Float(0)
        let inputRMSLeft = lastMeterValues[.inputRMSLeft]?.rms ?? Float(0)
        let inputRMSRight = lastMeterValues[.inputRMSRight]?.rms ?? Float(0)
        let outputRMSLeft = lastMeterValues[.outputRMSLeft]?.rms ?? Float(0)
        let outputRMSRight = lastMeterValues[.outputRMSRight]?.rms ?? Float(0)
        
        let allValues: [Float] = [
            inputPeakLeft, inputPeakRight, outputPeakLeft, outputPeakRight,
            inputRMSLeft, inputRMSRight, outputRMSLeft, outputRMSRight
        ]
        
        let inputHoldLeft = lastMeterValues[.inputPeakLeft]?.peakHold ?? Float(0)
        let inputHoldRight = lastMeterValues[.inputPeakRight]?.peakHold ?? Float(0)
        let outputHoldLeft = lastMeterValues[.outputPeakLeft]?.peakHold ?? Float(0)
        let outputHoldRight = lastMeterValues[.outputPeakRight]?.peakHold ?? Float(0)
        
        let allHolds: [Float] = [inputHoldLeft, inputHoldRight, outputHoldLeft, outputHoldRight]
        
        let allValuesSilent = allValues.allSatisfy({ $0 < Self.atRestThreshold })
        let allHoldsSilent = allHolds.allSatisfy({ $0 < Self.atRestThreshold })
        metersAtRest = allValuesSilent && allHoldsSilent
    }
    
    private func updateMeter(type: MeterType, dbValue: Float, interval: TimeInterval) {
        var values = lastMeterValues[type] ?? MeterValues()
        
        let normalized = Self.normalize(db: dbValue)
        let delta = normalized - values.peak
        let smoothing = delta >= 0 ? Self.peakAttackSmoothing : Self.peakReleaseSmoothing
        let rawPeak = values.peak + delta * smoothing
        let peak = max(0, min(1, rawPeak))
        
        let isClipping = dbValue >= 0
        let actualPeakForHold = isClipping ? normalized : peak
        let isNewPeak = actualPeakForHold > values.peakHold
        
        let newHoldTime: TimeInterval
        let peakHold: Float
        if isNewPeak {
            newHoldTime = Self.peakHoldHoldDuration
            peakHold = actualPeakForHold
        } else if values.peakHoldTimeRemaining > 0 {
            newHoldTime = max(0, values.peakHoldTimeRemaining - interval)
            peakHold = values.peakHold
        } else {
            newHoldTime = 0
            let rawPeakHold = values.peakHold - Self.peakHoldDecayPerTick
            peakHold = max(0, min(1, rawPeakHold))
        }
        
        let clipHold = isClipping ? Self.clipHoldDuration : max(0, values.clipHold - interval)
        
        values.peak = peak
        values.peakHold = peakHold
        values.peakHoldTimeRemaining = newHoldTime
        values.clipHold = clipHold
        
        // Notify observers BEFORE storing new values so comparison uses old values
        notifyObservers(
            type: type,
            value: peak,
            hold: peakHold,
            clipping: clipHold > 0
        )
        
        lastMeterValues[type] = values
    }
    
    private func updateRMSMeter(type: MeterType, dbValue: Float) {
        var values = lastMeterValues[type] ?? MeterValues()
        
        let normalized = Self.normalize(db: dbValue)
        let delta = normalized - values.rms
        let rawRMS = values.rms + delta * Self.rmsSmoothing
        let rms = max(0, min(1, rawRMS))
        
        values.rms = rms
        
        // Notify observers BEFORE storing new values so comparison uses old values
        notifyObservers(type: type, value: rms, hold: 0, clipping: false)
        
        lastMeterValues[type] = values
    }
    
    private func notifyObservers(type: MeterType, value: Float, hold: Float, clipping: Bool) {
        // Check if value changed enough to notify
        if let last = lastMeterValues[type] {
            let lastTotal = last.peak + last.peakHold
            let newTotal = value + hold
            if abs(newTotal - lastTotal) < Self.changeThreshold && !clipping {
                return
            }
        }
        
        observerQueue.sync {
            guard let typeObservers = observers[type] else { return }
            
            for wrapper in typeObservers {
                wrapper.observer?.meterUpdated(value: value, hold: hold, clipping: clipping)
            }
        }
    }
    
    private func notifyAllObserversSilent() {
        observerQueue.sync {
            for type in MeterType.allCases {
                guard let typeObservers = observers[type] else { continue }
                for wrapper in typeObservers {
                    wrapper.observer?.meterUpdated(value: 0, hold: 0, clipping: false)
                }
            }
        }
        
        // Reset stored values
        lastMeterValues.removeAll()
    }
    
    // MARK: - Utility
    
    private static func normalize(db: Float) -> Float {
        if db <= meterRange.lowerBound {
            return 0
        }
        if db >= meterRange.upperBound {
            return 1
        }
        let amp = powf(10.0, 0.05 * db)
        let minAmp = powf(10.0, 0.05 * meterRange.lowerBound)
        let maxAmp = powf(10.0, 0.05 * meterRange.upperBound)
        let normalizedAmp = (amp - minAmp) / (maxAmp - minAmp)
        return powf(normalizedAmp, gamma)
    }
}
