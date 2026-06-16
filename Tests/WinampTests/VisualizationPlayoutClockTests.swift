import XCTest

@testable import Winamp

final class VisualizationPlayoutClockTests: XCTestCase {
    func testStartsAtFirstFrameOnArrival() {
        let index = VisualizationPlayoutClock.frameIndex(
            now: 100,
            batchArrival: 100,
            frameCount: 18,
            batchDuration: 0.1
        )
        XCTAssertEqual(index, 0)
    }

    func testAdvancesLinearlyAcrossBatch() {
        // Halfway through a 0.1 s batch of 18 frames → roughly the middle frame
        // (index 8 or 9 depending on floating-point rounding at the boundary).
        let index = VisualizationPlayoutClock.frameIndex(
            now: 100.05,
            batchArrival: 100,
            frameCount: 18,
            batchDuration: 0.1
        )
        XCTAssertTrue((8 ... 9).contains(index), "expected mid-batch frame, got \(index)")
    }

    func testReachesLastFrameAtEndOfBatch() {
        let index = VisualizationPlayoutClock.frameIndex(
            now: 100.0999,
            batchArrival: 100,
            frameCount: 18,
            batchDuration: 0.1
        )
        XCTAssertEqual(index, 17)
    }

    func testHoldsOnLastFrameWhenOverdue() {
        // A follow-up buffer is late: clamp to the newest frame, never wrap back.
        let index = VisualizationPlayoutClock.frameIndex(
            now: 100.25,
            batchArrival: 100,
            frameCount: 18,
            batchDuration: 0.1
        )
        XCTAssertEqual(index, 17)
    }

    func testNegativeElapsedClampsToFirstFrame() {
        let index = VisualizationPlayoutClock.frameIndex(
            now: 99.9,
            batchArrival: 100,
            frameCount: 18,
            batchDuration: 0.1
        )
        XCTAssertEqual(index, 0)
    }

    func testZeroDurationReturnsNewestFrame() {
        // Single-shot publish (no intra-buffer detail) maps to the last frame.
        let index = VisualizationPlayoutClock.frameIndex(
            now: 100,
            batchArrival: 100,
            frameCount: 4,
            batchDuration: 0
        )
        XCTAssertEqual(index, 3)
    }

    func testEmptyBatchReturnsZero() {
        let index = VisualizationPlayoutClock.frameIndex(
            now: 100,
            batchArrival: 100,
            frameCount: 0,
            batchDuration: 0.1
        )
        XCTAssertEqual(index, 0)
    }

    func testSingleFrameBatchReturnsZero() {
        let index = VisualizationPlayoutClock.frameIndex(
            now: 100.05,
            batchArrival: 100,
            frameCount: 1,
            batchDuration: 0.1
        )
        XCTAssertEqual(index, 0)
    }
}
