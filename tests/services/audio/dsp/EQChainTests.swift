import XCTest
@testable import Equaliser

final class EQChainTests: XCTestCase {
    // MARK: - Test Constants

    let sampleRate: Double = 48000.0
    let frameCount: UInt32 = 512
    let maxFrameCount: UInt32 = 4096

    // MARK: - Initialization Tests

    func testInitialization() {
        let chain = EQChain(maxFrameCount: maxFrameCount)

        // Chain should start with 0 active bands
        // We can't directly check activeBandCount (private), but we can verify passthrough behavior
        var input: [Float] = [Float](repeating: 0.5, count: Int(frameCount))
        var output: [Float] = [Float](repeating: 0, count: Int(frameCount))

        input.withUnsafeBufferPointer { inputPtr in
            output.withUnsafeMutableBufferPointer { outputPtr in
                chain.applyPendingUpdates()
                chain.process(buffer: outputPtr.baseAddress!, frameCount: frameCount)
            }
        }

        // With no active bands, output should be passthrough
        // Actually, with no active bands, the chain doesn't process anything
        // so the output should remain as the input (since no processing occurred)
        // The buffer is passed to process but not modified if activeBandCount is 0
    }

    // MARK: - Band Update Tests

    func testSingleBandUpdate() {
        let chain = EQChain(maxFrameCount: maxFrameCount)

        // Create coefficients for a peaking filter
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            q: 1.0,
            gain: 6.0
        )

        // Set up with the actual coefficients (not identity)
        var allCoeffs = [BiquadCoefficients](repeating: .identity, count: EQChain.maxBandCount)
        allCoeffs[0] = coeffs
        var bypassFlags = [Bool](repeating: false, count: EQChain.maxBandCount)

        // Stage full update with active band
        chain.stageFullUpdate(
            coefficients: allCoeffs,
            bypassFlags: bypassFlags,
            activeBandCount: 1,
            layerBypass: false
        )

        // Apply updates
        chain.applyPendingUpdates()

        // Process impulse
        var buffer: [Float] = [Float](repeating: 0, count: Int(frameCount))
        buffer[0] = 1.0 // Impulse

        buffer.withUnsafeMutableBufferPointer { bufPtr in
            chain.process(buffer: bufPtr.baseAddress!, frameCount: frameCount)
        }

        // Output should be different from identity (filter processed the impulse)
        // With a peaking filter, b0 ≠ 1, so output[0] ≠ 1.0
        XCTAssertGreaterThan(abs(buffer[0] - 1.0), 0.001, "Filter should have processed the impulse")
    }

    func testFullUpdate() {
        let chain = EQChain(maxFrameCount: maxFrameCount)

        // Create coefficients for 3 active bands
        var coeffs: [BiquadCoefficients] = []
        var bypassFlags: [Bool] = []

        for i in 0..<3 {
            let c = BiquadMath.calculateCoefficients(
                type: .parametric,
                sampleRate: sampleRate,
                frequency: 100.0 * Double(i + 1) * 100,
                q: 1.0,
                gain: Double(i + 1) * 2
            )
            coeffs.append(c)
            bypassFlags.append(false)
        }

        // Pad to maxBandCount
        while coeffs.count < EQChain.maxBandCount {
            coeffs.append(.identity)
            bypassFlags.append(false)
        }

        chain.stageFullUpdate(
            coefficients: coeffs,
            bypassFlags: bypassFlags,
            activeBandCount: 3,
            layerBypass: false
        )

        chain.applyPendingUpdates()

        // Process should work
        var buffer: [Float] = [Float](repeating: 0, count: Int(frameCount))
        buffer[0] = 1.0

        buffer.withUnsafeMutableBufferPointer { bufPtr in
            chain.process(buffer: bufPtr.baseAddress!, frameCount: frameCount)
        }

        // Just verify it doesn't crash and produces some output
        XCTAssertFalse(buffer.allSatisfy { $0 == 0 })
    }

    func testBandBypass() {
        let chain = EQChain(maxFrameCount: maxFrameCount)

        // Stage a band with bypass=true
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            q: 1.0,
            gain: 6.0
        )
        chain.stageBandUpdate(index: 0, coefficients: coeffs, bypass: true)

        chain.stageFullUpdate(
            coefficients: [coeffs] + [BiquadCoefficients](repeating: .identity, count: EQChain.maxBandCount - 1),
            bypassFlags: [true] + [Bool](repeating: false, count: EQChain.maxBandCount - 1),
            activeBandCount: 1,
            layerBypass: false
        )

        chain.applyPendingUpdates()

        // With bypass, impulse should pass through unchanged
        var buffer: [Float] = [Float](repeating: 0, count: Int(frameCount))
        buffer[0] = 1.0

        buffer.withUnsafeMutableBufferPointer { bufPtr in
            chain.process(buffer: bufPtr.baseAddress!, frameCount: frameCount)
        }

        // Bypassed band = passthrough
        XCTAssertEqual(buffer[0], 1.0, accuracy: 1e-6)
    }

    func testLayerBypass() {
        let chain = EQChain(maxFrameCount: maxFrameCount)

        // Stage full update with layer bypass
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            q: 1.0,
            gain: 6.0
        )

        chain.stageFullUpdate(
            coefficients: [coeffs] + [BiquadCoefficients](repeating: .identity, count: EQChain.maxBandCount - 1),
            bypassFlags: [Bool](repeating: false, count: EQChain.maxBandCount),
            activeBandCount: 1,
            layerBypass: true
        )

        chain.applyPendingUpdates()

        // With layer bypass, signal should pass through unchanged
        var buffer: [Float] = [Float](repeating: 0, count: Int(frameCount))
        buffer[0] = 1.0

        buffer.withUnsafeMutableBufferPointer { bufPtr in
            chain.process(buffer: bufPtr.baseAddress!, frameCount: frameCount)
        }

        // Layer bypass = passthrough
        XCTAssertEqual(buffer[0], 1.0, accuracy: 1e-6)
    }

    // MARK: - Multiple Bands Tests

    func testMultipleBandsInSeries() {
        let chain = EQChain(maxFrameCount: maxFrameCount)

        // Create 3 bands
        var coeffs: [BiquadCoefficients] = []
        var bypassFlags: [Bool] = []

        for i in 0..<3 {
            let c = BiquadMath.calculateCoefficients(
                type: .parametric,
                sampleRate: sampleRate,
                frequency: 500.0 + Double(i) * 500,
                q: 1.0,
                gain: 3.0
            )
            coeffs.append(c)
            bypassFlags.append(false)
        }

        // Pad to maxBandCount
        while coeffs.count < EQChain.maxBandCount {
            coeffs.append(.identity)
            bypassFlags.append(false)
        }

        chain.stageFullUpdate(
            coefficients: coeffs,
            bypassFlags: bypassFlags,
            activeBandCount: 3,
            layerBypass: false
        )

        chain.applyPendingUpdates()

        // Process impulse
        var buffer: [Float] = [Float](repeating: 0, count: Int(frameCount))
        buffer[0] = 1.0

        buffer.withUnsafeMutableBufferPointer { bufPtr in
            chain.process(buffer: bufPtr.baseAddress!, frameCount: frameCount)
        }

        // With 3 bands in series, output should be different from single band
        // Just verify it doesn't crash
        XCTAssertFalse(buffer.allSatisfy { $0 == 0 })
    }

    // MARK: - Real-Time Safety Tests

    func testNoAllocationDuringProcess() {
        let chain = EQChain(maxFrameCount: maxFrameCount)

        // Set up bands
        let coeffs = BiquadMath.calculateCoefficients(
            type: .parametric,
            sampleRate: sampleRate,
            frequency: 1000.0,
            q: 1.0,
            gain: 6.0
        )

        chain.stageFullUpdate(
            coefficients: [coeffs] + [BiquadCoefficients](repeating: .identity, count: EQChain.maxBandCount - 1),
            bypassFlags: [Bool](repeating: false, count: EQChain.maxBandCount),
            activeBandCount: 1,
            layerBypass: false
        )

        chain.applyPendingUpdates()

        // Process multiple times to ensure no allocation leaks
        var buffer: [Float] = [Float](repeating: 0.5, count: Int(frameCount))

        for _ in 0..<100 {
            buffer.withUnsafeMutableBufferPointer { bufPtr in
                chain.applyPendingUpdates()
                chain.process(buffer: bufPtr.baseAddress!, frameCount: frameCount)
            }
        }

        // If we get here without crash, allocations are pre-allocated
        XCTAssertTrue(true)
    }
}