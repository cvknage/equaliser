import AppKit
import Combine
import Foundation
import os.log

@MainActor
final class MeterStore: ObservableObject {
    @Published var inputMeterLevel: StereoMeterState = .silent
    @Published var outputMeterLevel: StereoMeterState = .silent
    @Published var inputMeterRMS: StereoMeterState = .silent
    @Published var outputMeterRMS: StereoMeterState = .silent

    @Published var metersEnabled: Bool = true {
        didSet {
            storage.set(metersEnabled, forKey: Keys.metersEnabled)
            if !metersEnabled {
                inputMeterLevel = .silent
                outputMeterLevel = .silent
                inputMeterRMS = .silent
                outputMeterRMS = .silent
                metersAtRest = true
            }
        }
    }

    private weak var renderPipeline: RenderPipeline?
    private weak var equaliserWindow: NSWindow?
    private let storage: UserDefaults

    private var meterTimer: AnyCancellable?
    private var metersAtRest = false
    private let logger = Logger(subsystem: "net.knage.equaliser", category: "MeterStore")

    private static let meterInterval: TimeInterval = 1.0 / 30.0
    private static let peakHoldHoldDuration: TimeInterval = 1.0
    private static let peakHoldDecayPerTick: Float = 0.02
    private static let peakAttackSmoothing: Float = 0.8
    private static let peakReleaseSmoothing: Float = 0.33
    private static let rmsSmoothing: Float = 0.12
    private static let clipHoldDuration: TimeInterval = 0.5
    private static let meterRange: ClosedRange<Float> = Float(-36)...Float(0)
    private static let gamma: Float = 0.5

    private enum Keys {
        static let metersEnabled = "equalizer.metersEnabled"
    }

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        let storedMetersEnabled = storage.object(forKey: Keys.metersEnabled) as? Bool ?? true
        _metersEnabled = Published(initialValue: storedMetersEnabled)
    }

    func setRenderPipeline(_ pipeline: RenderPipeline?) {
        self.renderPipeline = pipeline
    }

    func setEqualiserWindow(_ window: NSWindow?) {
        self.equaliserWindow = window
    }

    func startMeterUpdates() {
        meterTimer?.cancel()
        guard renderPipeline != nil else { return }

        meterTimer = Timer.publish(every: Self.meterInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMeterSnapshot()
            }
    }

    func stopMeterUpdates() {
        meterTimer?.cancel()
        meterTimer = nil
        inputMeterLevel = .silent
        outputMeterLevel = .silent
        inputMeterRMS = .silent
        outputMeterRMS = .silent
    }

    private func refreshMeterSnapshot() {
        guard metersEnabled else { return }

        if let window = equaliserWindow {
            guard window.isVisible else { return }
        } else if let keyWindow = NSApp.keyWindow {
            guard keyWindow.isVisible else { return }
        }

        guard let pipeline = renderPipeline else { return }

        if metersAtRest {
            let snapshot = pipeline.currentMeters()
            let silenceThreshold: Float = -85
            let stillSilent = snapshot.inputDB.allSatisfy({ $0 <= silenceThreshold }) &&
                              snapshot.outputDB.allSatisfy({ $0 <= silenceThreshold }) &&
                              snapshot.inputRmsDB.allSatisfy({ $0 <= silenceThreshold }) &&
                              snapshot.outputRmsDB.allSatisfy({ $0 <= silenceThreshold })

            if stillSilent {
                return
            }
            metersAtRest = false
        }

        let snapshot = pipeline.currentMeters()

        inputMeterLevel = meterState(from: snapshot.inputDB, previous: inputMeterLevel)
        outputMeterLevel = meterState(from: snapshot.outputDB, previous: outputMeterLevel)
        inputMeterRMS = rmsState(from: snapshot.inputRmsDB, previous: inputMeterRMS)
        outputMeterRMS = rmsState(from: snapshot.outputRmsDB, previous: outputMeterRMS)

        let atRestThreshold: Float = 0.01
        metersAtRest = inputMeterLevel.left.peak < atRestThreshold &&
                       inputMeterLevel.right.peak < atRestThreshold &&
                       inputMeterLevel.left.peakHold < atRestThreshold &&
                       inputMeterLevel.right.peakHold < atRestThreshold &&
                       outputMeterLevel.left.peak < atRestThreshold &&
                       outputMeterLevel.right.peak < atRestThreshold &&
                       outputMeterLevel.left.peakHold < atRestThreshold &&
                       outputMeterLevel.right.peakHold < atRestThreshold &&
                       inputMeterRMS.left.rms < atRestThreshold &&
                       inputMeterRMS.right.rms < atRestThreshold &&
                       outputMeterRMS.left.rms < atRestThreshold &&
                       outputMeterRMS.right.rms < atRestThreshold
    }

    private func rmsState(from dbValues: [Float], previous: StereoMeterState) -> StereoMeterState {
        let left = channelRMSState(from: dbValues, channelIndex: 0, previous: previous.left)
        let right = channelRMSState(from: dbValues, channelIndex: 1, previous: previous.right)
        return StereoMeterState(left: left, right: right)
    }

    private func channelRMSState(from dbValues: [Float], channelIndex: Int, previous: ChannelMeterState) -> ChannelMeterState {
        let db = dbValues.indices.contains(channelIndex) ? dbValues[channelIndex] : Self.meterRange.lowerBound
        let normalized = Self.normalize(db: db)
        let delta = normalized - previous.rms
        let rawRMS = previous.rms + delta * Self.rmsSmoothing
        let rms = max(0, min(1, rawRMS))

        let zeroThreshold: Float = 0.005
        let clampedRMS = rms < zeroThreshold ? 0 : rms

        return ChannelMeterState(
            peak: previous.peak,
            peakHold: previous.peakHold,
            peakHoldTimeRemaining: previous.peakHoldTimeRemaining,
            clipHold: previous.clipHold,
            rms: clampedRMS
        )
    }

    private func meterState(from dbValues: [Float], previous: StereoMeterState) -> StereoMeterState {
        let left = channelState(from: dbValues, channelIndex: 0, previous: previous.left)
        let right = channelState(from: dbValues, channelIndex: 1, previous: previous.right)
        return StereoMeterState(left: left, right: right)
    }

    private func channelState(from dbValues: [Float], channelIndex: Int, previous: ChannelMeterState) -> ChannelMeterState {
        let db = dbValues.indices.contains(channelIndex) ? dbValues[channelIndex] : Self.meterRange.lowerBound
        let normalized = Self.normalize(db: db)
        let delta = normalized - previous.peak
        let smoothing = delta >= 0 ? Self.peakAttackSmoothing : Self.peakReleaseSmoothing
        let rawPeak = previous.peak + delta * smoothing
        let zeroThreshold: Float = 0.005
        let peak = max(0, min(1, rawPeak)) < zeroThreshold ? 0 : max(0, min(1, rawPeak))

        let isClipping = db >= 0
        let actualPeakForHold = isClipping ? normalized : peak
        let isNewPeak = actualPeakForHold > previous.peakHold
        let newHoldTime: TimeInterval
        let peakHold: Float
        if isNewPeak {
            newHoldTime = Self.peakHoldHoldDuration
            peakHold = actualPeakForHold
        } else if previous.peakHoldTimeRemaining > 0 {
            newHoldTime = max(0, previous.peakHoldTimeRemaining - Self.meterInterval)
            peakHold = previous.peakHold
        } else {
            newHoldTime = 0
            let rawPeakHold = previous.peakHold - Self.peakHoldDecayPerTick
            let clampedPeakHold = rawPeakHold < zeroThreshold ? 0 : max(0, min(1, rawPeakHold))
            peakHold = clampedPeakHold
        }

        let clipHold = isClipping ? Self.clipHoldDuration : max(0, previous.clipHold - Self.meterInterval)
        return ChannelMeterState(peak: peak, peakHold: peakHold, peakHoldTimeRemaining: newHoldTime, clipHold: clipHold, rms: previous.rms)
    }

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
