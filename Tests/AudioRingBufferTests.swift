import XCTest
@testable import EqualiserApp

final class AudioRingBufferTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInit_roundsUpToPowerOfTwo() {
        // 100 -> 128
        let buffer100 = AudioRingBuffer(capacity: 100)
        XCTAssertEqual(buffer100.getCapacity(), 128)

        // 3 -> 4
        let buffer3 = AudioRingBuffer(capacity: 3)
        XCTAssertEqual(buffer3.getCapacity(), 4)

        // 256 -> 256 (already power of 2)
        let buffer256 = AudioRingBuffer(capacity: 256)
        XCTAssertEqual(buffer256.getCapacity(), 256)

        // 1 -> 2 (minimum power of 2)
        let buffer1 = AudioRingBuffer(capacity: 1)
        XCTAssertEqual(buffer1.getCapacity(), 2)

        // 17 -> 32
        let buffer17 = AudioRingBuffer(capacity: 17)
        XCTAssertEqual(buffer17.getCapacity(), 32)
    }

    func testInit_startsEmpty() {
        let buffer = AudioRingBuffer(capacity: 64)

        XCTAssertEqual(buffer.availableToRead(), 0)
        XCTAssertEqual(buffer.availableToWrite(), buffer.getCapacity())
    }

    // MARK: - Write/Read Basic Tests

    func testWriteRead_simpleData() {
        let buffer = AudioRingBuffer(capacity: 64)
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]

        // Write samples
        let written = samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: samples.count)
        }
        XCTAssertEqual(written, 5)
        XCTAssertEqual(buffer.availableToRead(), 5)

        // Read samples
        var output = [Float](repeating: 0, count: 5)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 5)
        }
        XCTAssertEqual(read, 5)
        XCTAssertEqual(output, samples)
        XCTAssertEqual(buffer.availableToRead(), 0)
    }

    func testWriteRead_exactCapacity() {
        let buffer = AudioRingBuffer(capacity: 8) // Will be 8 since it's already power of 2
        let capacity = buffer.getCapacity()

        // Generate samples to fill buffer exactly
        let samples = (0..<capacity).map { Float($0) }

        // Write to fill completely
        let written = samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: samples.count)
        }
        XCTAssertEqual(written, capacity)
        XCTAssertEqual(buffer.availableToRead(), capacity)
        XCTAssertEqual(buffer.availableToWrite(), 0)

        // Read all
        var output = [Float](repeating: 0, count: capacity)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: capacity)
        }
        XCTAssertEqual(read, capacity)
        XCTAssertEqual(output, samples)
    }

    func testWriteRead_wrapAround() {
        let buffer = AudioRingBuffer(capacity: 8)

        // Write half capacity
        let firstHalf = (0..<4).map { Float($0) }
        _ = firstHalf.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: firstHalf.count)
        }

        // Read half capacity (advances read pointer)
        var discard = [Float](repeating: 0, count: 4)
        _ = discard.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 4)
        }

        // Write 6 samples (will wrap around)
        let wrappingData: [Float] = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        let written = wrappingData.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: wrappingData.count)
        }
        XCTAssertEqual(written, 6)

        // Read back - should get the wrapped data correctly
        var output = [Float](repeating: 0, count: 6)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 6)
        }
        XCTAssertEqual(read, 6)
        XCTAssertEqual(output, wrappingData)
    }

    // MARK: - Overflow Tests

    func testWrite_overflow_partialWrite() {
        let buffer = AudioRingBuffer(capacity: 8)
        let capacity = buffer.getCapacity()

        // Fill buffer partially
        let initial = [Float](repeating: 1.0, count: 6)
        _ = initial.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 6)
        }

        // Try to write more than available space
        let excess = [Float](repeating: 2.0, count: 4)
        let written = excess.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 4)
        }

        // Should only write what fits
        XCTAssertEqual(written, capacity - 6) // Only 2 spaces left
        XCTAssertEqual(buffer.availableToRead(), capacity)
    }

    func testWrite_fullBuffer_returnsZero() {
        let buffer = AudioRingBuffer(capacity: 8)
        let capacity = buffer.getCapacity()

        // Fill buffer completely
        let fillData = [Float](repeating: 1.0, count: capacity)
        _ = fillData.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: capacity)
        }

        // Try to write more
        let moreData: [Float] = [2.0]
        let written = moreData.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 1)
        }

        XCTAssertEqual(written, 0)
    }

    // MARK: - Underrun Tests

    func testRead_underrun_zeroFills() {
        let buffer = AudioRingBuffer(capacity: 16)

        // Write only 3 samples
        let samples: [Float] = [1.0, 2.0, 3.0]
        _ = samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 3)
        }

        // Try to read 5 samples
        var output = [Float](repeating: -1.0, count: 5)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 5)
        }

        // Should read 3 actual samples and zero-fill 2
        XCTAssertEqual(read, 3)
        XCTAssertEqual(output[0], 1.0)
        XCTAssertEqual(output[1], 2.0)
        XCTAssertEqual(output[2], 3.0)
        XCTAssertEqual(output[3], 0.0) // Zero-filled
        XCTAssertEqual(output[4], 0.0) // Zero-filled
    }

    func testRead_emptyBuffer_zeroFills() {
        let buffer = AudioRingBuffer(capacity: 16)

        // Read from empty buffer
        var output = [Float](repeating: -1.0, count: 4)
        let read = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 4)
        }

        // Should return 0 read and zero-fill all
        XCTAssertEqual(read, 0)
        XCTAssertEqual(output, [0.0, 0.0, 0.0, 0.0])
    }

    // MARK: - Reset Tests

    func testReset_clearsBuffer() {
        let buffer = AudioRingBuffer(capacity: 16)

        // Write some data
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0]
        _ = samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 4)
        }
        XCTAssertEqual(buffer.availableToRead(), 4)

        // Reset
        buffer.reset()

        // Buffer should be empty
        XCTAssertEqual(buffer.availableToRead(), 0)
        XCTAssertEqual(buffer.availableToWrite(), buffer.getCapacity())

        // Counters should be reset
        XCTAssertEqual(buffer.getOverflowCount(), 0)
        XCTAssertEqual(buffer.getUnderrunCount(), 0)
    }

    // MARK: - Available Count Tests

    func testAvailableToRead_afterOperations() {
        let buffer = AudioRingBuffer(capacity: 16)

        XCTAssertEqual(buffer.availableToRead(), 0)

        // Write 5 samples
        let samples = [Float](repeating: 1.0, count: 5)
        _ = samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 5)
        }
        XCTAssertEqual(buffer.availableToRead(), 5)

        // Read 3 samples
        var output = [Float](repeating: 0, count: 3)
        _ = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 3)
        }
        XCTAssertEqual(buffer.availableToRead(), 2)

        // Read remaining
        _ = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 2)
        }
        XCTAssertEqual(buffer.availableToRead(), 0)
    }

    // MARK: - Overflow/Underrun Counter Tests

    func testOverflowCount_increments() {
        let buffer = AudioRingBuffer(capacity: 4) // Capacity will be 4
        let capacity = buffer.getCapacity()

        XCTAssertEqual(buffer.getOverflowCount(), 0)

        // Fill buffer
        let fillData = [Float](repeating: 1.0, count: capacity)
        _ = fillData.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: capacity)
        }

        // Try to write more (causes overflow)
        let moreData: [Float] = [2.0, 3.0]
        _ = moreData.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 2)
        }

        XCTAssertEqual(buffer.getOverflowCount(), 1)

        // Another overflow attempt
        _ = moreData.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 2)
        }

        XCTAssertEqual(buffer.getOverflowCount(), 2)
    }

    func testUnderrunCount_increments() {
        let buffer = AudioRingBuffer(capacity: 16)

        XCTAssertEqual(buffer.getUnderrunCount(), 0)

        // Read from empty buffer (causes underrun)
        var output = [Float](repeating: 0, count: 4)
        _ = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 4)
        }

        XCTAssertEqual(buffer.getUnderrunCount(), 1)

        // Another underrun
        _ = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 4)
        }

        XCTAssertEqual(buffer.getUnderrunCount(), 2)
    }

    func testUnderrunCount_incrementsOnPartialRead() {
        let buffer = AudioRingBuffer(capacity: 16)

        // Write 2 samples
        let samples: [Float] = [1.0, 2.0]
        _ = samples.withUnsafeBufferPointer { ptr in
            buffer.write(ptr.baseAddress!, count: 2)
        }

        XCTAssertEqual(buffer.getUnderrunCount(), 0)

        // Try to read 5 samples (partial underrun)
        var output = [Float](repeating: 0, count: 5)
        _ = output.withUnsafeMutableBufferPointer { ptr in
            buffer.read(into: ptr.baseAddress!, count: 5)
        }

        XCTAssertEqual(buffer.getUnderrunCount(), 1)
    }
}
