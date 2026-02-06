import AVFoundation
import os.log

@MainActor
final class AudioEngineManager {
    private let engine = AVAudioEngine()
    private let eqUnitA = AVAudioUnitEQ(numberOfBands: 16)
    private let eqUnitB = AVAudioUnitEQ(numberOfBands: 16)
    private let logger = Logger(subsystem: "com.example.EqualizerApp", category: "AudioEngine")

    private(set) var isRunning: Bool = false

    init() {
        configureBands()
        configureLimiter()
        setupGraph()
    }

    func start() {
        guard !isRunning else { return }
        do {
            try engine.start()
            isRunning = true
            logger.info("Audio engine started")
        } catch {
            logger.error("Failed to start engine: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine.stop()
        isRunning = false
        logger.info("Audio engine stopped")
    }

    func setBypassed(_ bypassed: Bool) {
        eqUnitA.bypass = bypassed
        eqUnitB.bypass = bypassed
    }

    func updateBandGain(index: Int, gain: Float) {
        let (unit, bandIndex) = bandMapping(for: index)
        unit.bands[bandIndex].gain = gain
    }

    func updateBandBandwidth(index: Int, bandwidth: Float) {
        let (unit, bandIndex) = bandMapping(for: index)
        unit.bands[bandIndex].bandwidth = bandwidth
    }

    func updateBandFrequency(index: Int, frequency: Float) {
        let (unit, bandIndex) = bandMapping(for: index)
        unit.bands[bandIndex].frequency = frequency
    }

    private func bandMapping(for index: Int) -> (AVAudioUnitEQ, Int) {
        if index < 16 {
            return (eqUnitA, index)
        } else {
            return (eqUnitB, index - 16)
        }
    }

    private func configureBands() {
        let defaultFrequencies: [Float] = [
            31.5, 40, 50, 63, 80, 100, 125, 160,
            200, 250, 315, 400, 500, 630, 800, 1000,
            1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300,
            8000, 10000, 12500, 16000, 20000, 22050, 24000, 26000
        ]
        let bandwidth: Float = 0.67

        for (index, frequency) in defaultFrequencies.enumerated() {
            let (unit, bandIndex) = bandMapping(for: index)
            let band = unit.bands[bandIndex]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = bandwidth
            band.gain = 0
            band.bypass = false
        }
    }

    private func configureLimiter() {}

    private func setupGraph() {
        engine.attach(eqUnitA)
        engine.attach(eqUnitB)

        let format = engine.inputNode.outputFormat(forBus: 0)

        engine.connect(engine.inputNode, to: eqUnitA, format: format)
        engine.connect(eqUnitA, to: eqUnitB, format: format)
        engine.connect(eqUnitB, to: engine.mainMixerNode, format: format)
    }
}
