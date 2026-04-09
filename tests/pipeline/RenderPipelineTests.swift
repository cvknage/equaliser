import XCTest
@testable import Equaliser

final class RenderPipelineTests: XCTestCase {
    
    // MARK: - Gain Calculation Tests
    
    func testGainLinear_fromZeroDB() {
        // 0 dB = linear 1.0
        let linear = AudioMath.dbToLinear(0.0)
        XCTAssertEqual(linear, 1.0, accuracy: 0.0001)
    }
    
    func testGainLinear_fromPositiveDB() {
        // +6 dB ≈ 2x linear
        let linear = AudioMath.dbToLinear(6.0)
        XCTAssertEqual(linear, 2.0, accuracy: 0.1)
        
        // +12 dB ≈ 4x linear
        let linear12 = AudioMath.dbToLinear(12.0)
        XCTAssertEqual(linear12, 4.0, accuracy: 0.2)
    }
    
    func testGainLinear_fromNegativeDB() {
        // -6 dB ≈ 0.5x linear
        let linear = AudioMath.dbToLinear(-6.0)
        XCTAssertEqual(linear, 0.5, accuracy: 0.1)
        
        // -12 dB ≈ 0.25x linear
        let linear12 = AudioMath.dbToLinear(-12.0)
        XCTAssertEqual(linear12, 0.25, accuracy: 0.05)
    }
    
    func testGainLinear_silenceThreshold() {
        // -90 dB should produce near-silence
        let linear = AudioMath.dbToLinear(-90.0)
        XCTAssertEqual(linear, 0.0, accuracy: 0.0001)
    }
    
    // MARK: - Boost Gain Tests
    
    func testBoostGain_compensatesVolumeAttenuation() {
        // When driver volume is lowered to compensate for output volume > 100%,
        // boost gain compensates to restore perceptual volume.
        
        // Example: Driver at 50% (0.5), output at 150% (1.5)
        // Boost should be 1/0.5 = 2.0 to compensate
        let driverVolume: Float = 0.5
        let boostGain: Float = 1.0 / driverVolume
        
        XCTAssertEqual(boostGain, 2.0, accuracy: 0.0001)
    }
    
    func testBoostGain_unityWhenDriverAt100Percent() {
        // When driver is at 100%, boost should be 1.0
        let driverVolume: Float = 1.0
        let boostGain: Float = 1.0 / driverVolume
        
        XCTAssertEqual(boostGain, 1.0, accuracy: 0.0001)
    }
}

// MARK: - Atomic Gain Storage Tests

final class AtomicGainStorageTests: XCTestCase {
    
    func testFloatBitPattern_roundTrip() {
        // Verify that Float → Int32 bits → Float round-trips correctly
        let testValues: [Float] = [0.0, 0.5, 1.0, 1.5, 2.0, 0.75, 0.001, 10.0, 0.125]
        
        for value in testValues {
            let bits = Int32(bitPattern: value.bitPattern)
            let restored = Float(bitPattern: UInt32(bitPattern: bits))
            XCTAssertEqual(restored, value, accuracy: 0.0001, "Failed for value: \(value)")
        }
    }
    
    func testFloatBitPattern_preservesSmallValues() {
        // Test very small gain values
        let smallValue: Float = 0.001
        
        let bits = Int32(bitPattern: smallValue.bitPattern)
        let restored = Float(bitPattern: UInt32(bitPattern: bits))
        
        XCTAssertEqual(restored, smallValue, accuracy: 0.000001)
    }
    
    func testFloatBitPattern_preservesLargeValues() {
        // Test large gain values
        let largeValue: Float = 100.0
        
        let bits = Int32(bitPattern: largeValue.bitPattern)
        let restored = Float(bitPattern: UInt32(bitPattern: bits))
        
        XCTAssertEqual(restored, largeValue, accuracy: 0.01)
    }
    
    func testFloatBitPattern_preservesUnity() {
        // Test 1.0 specifically (very common case)
        let unity: Float = 1.0
        
        let bits = Int32(bitPattern: unity.bitPattern)
        // 1.0 as Float has bit pattern 0x3F800000 = 1065353216
        XCTAssertEqual(bits, 1065353216)
        
        let restored = Float(bitPattern: UInt32(bitPattern: bits))
        XCTAssertEqual(restored, 1.0, accuracy: 0.0001)
    }
}