import XCTest

@testable import Winamp

final class SongMarqueeAnimationTests: XCTestCase {
    // MARK: - horizontalOffset

    func testHorizontalOffsetStartsAtZero() {
        let offset = SongMarqueeAnimation.horizontalOffset(
            elapsed: 0, speed: 10, scrollDistance: 100)
        XCTAssertEqual(offset, 0, accuracy: 0.0001)
    }

    func testHorizontalOffsetAdvancesNegativelyWithTime() {
        // 10 pt/s for 2 s → -20 pt.
        let offset = SongMarqueeAnimation.horizontalOffset(
            elapsed: 2, speed: 10, scrollDistance: 1000)
        XCTAssertEqual(offset, -20, accuracy: 0.0001)
    }

    func testHorizontalOffsetWrapsAtScrollDistance() {
        // 10 pt/s for 12 s = 120 pt, wraps modulo 100 → -20 pt.
        let offset = SongMarqueeAnimation.horizontalOffset(
            elapsed: 12, speed: 10, scrollDistance: 100)
        XCTAssertEqual(offset, -20, accuracy: 0.0001)
    }

    func testHorizontalOffsetZeroDistanceIsSafe() {
        let offset = SongMarqueeAnimation.horizontalOffset(elapsed: 5, speed: 10, scrollDistance: 0)
        XCTAssertEqual(offset, 0)
    }

    // MARK: - scrollUp

    func testScrollUpStartsAtFirstText() {
        let frame = SongMarqueeAnimation.scrollUp(
            elapsed: 0, speed: 10, totalDistance: 100, centerOffset: 50, pause: 2.5
        )
        XCTAssertEqual(frame.textIndex, 0)
        XCTAssertEqual(frame.offset, 0, accuracy: 0.0001)
    }

    func testScrollUpHoldsAtCenterDuringPause() {
        // centerTime = 50/10 = 5 s; during the pause (5 ..< 7.5 s) offset stays at center.
        let frame = SongMarqueeAnimation.scrollUp(
            elapsed: 6, speed: 10, totalDistance: 100, centerOffset: 50, pause: 2.5
        )
        XCTAssertEqual(frame.offset, 50, accuracy: 0.0001)
    }

    func testScrollUpResumesAfterPause() {
        // After the 2.5 s pause: at 8.5 s, offset = (8.5 - 2.5) * 10 = 60.
        let frame = SongMarqueeAnimation.scrollUp(
            elapsed: 8.5, speed: 10, totalDistance: 100, centerOffset: 50, pause: 2.5
        )
        XCTAssertEqual(frame.offset, 60, accuracy: 0.0001)
    }

    func testScrollUpAlternatesTextEachSegment() {
        // segmentDuration = 100/10 + 2.5 = 12.5 s. Second segment → title.
        let frame = SongMarqueeAnimation.scrollUp(
            elapsed: 13, speed: 10, totalDistance: 100, centerOffset: 50, pause: 2.5
        )
        XCTAssertEqual(frame.textIndex, 1)
    }

    // MARK: - vestaboard

    func testVestaboardRevealsArtistCharactersOverTime() {
        // charInterval 0.1 → at 0.35 s, 3 chars revealed.
        let frame = SongMarqueeAnimation.vestaboard(
            elapsed: 0.35, artistCount: 10, titleCount: 5, charInterval: 0.1, showDuration: 3.0
        )
        XCTAssertEqual(frame.textIndex, 0)
        XCTAssertTrue(frame.isRevealing)
        XCTAssertEqual(frame.revealedChars, 3)
    }

    func testVestaboardEntersHoldPhaseAfterReveal() {
        // artistReveal = 10 * 0.1 = 1 s; at 1.5 s we're holding the artist.
        let frame = SongMarqueeAnimation.vestaboard(
            elapsed: 1.5, artistCount: 10, titleCount: 5, charInterval: 0.1, showDuration: 3.0
        )
        XCTAssertEqual(frame.textIndex, 0)
        XCTAssertFalse(frame.isRevealing)
        XCTAssertEqual(frame.revealedChars, 10)
        XCTAssertEqual(frame.showElapsed, 0.5, accuracy: 0.0001)
    }

    func testVestaboardMovesToTitleReveal() {
        // phase1End = 1 + 3 = 4 s; at 4.2 s the title is revealing (2 chars).
        let frame = SongMarqueeAnimation.vestaboard(
            elapsed: 4.2, artistCount: 10, titleCount: 5, charInterval: 0.1, showDuration: 3.0
        )
        XCTAssertEqual(frame.textIndex, 1)
        XCTAssertTrue(frame.isRevealing)
        XCTAssertEqual(frame.revealedChars, 2)
    }

    func testVestaboardCycleRepeats() {
        // cycle = 1 + 3 + 0.5 + 3 = 7.5 s; at 7.6 s we're back to revealing the artist.
        let frame = SongMarqueeAnimation.vestaboard(
            elapsed: 7.6, artistCount: 10, titleCount: 5, charInterval: 0.1, showDuration: 3.0
        )
        XCTAssertEqual(frame.textIndex, 0)
        XCTAssertTrue(frame.isRevealing)
    }

    // MARK: - pixelated

    func testPixelatedProgressAdvances() {
        // speed 0.667/s for 1.5 s → progress ≈ 1.0.
        let frame = SongMarqueeAnimation.pixelated(
            elapsed: 1.5, speed: 0.02 / 0.03, cycleProgress: 2.5)
        XCTAssertEqual(frame.textIndex, 0)
        XCTAssertEqual(frame.progress, 1.0, accuracy: 0.01)
    }

    func testPixelatedSwitchesTextAfterCycle() {
        // cycle ends at progress 2.5 → elapsed 2.5 / (0.667) ≈ 3.75 s; at 4 s → title.
        let frame = SongMarqueeAnimation.pixelated(
            elapsed: 4, speed: 0.02 / 0.03, cycleProgress: 2.5)
        XCTAssertEqual(frame.textIndex, 1)
    }

    // MARK: - characterOffset

    func testCharacterOffsetIsDeterministic() {
        XCTAssertEqual(
            SongMarqueeAnimation.characterOffset(index: 7),
            SongMarqueeAnimation.characterOffset(index: 7)
        )
    }

    func testCharacterOffsetStaysWithinRange() {
        for index in 0..<200 {
            let offset = SongMarqueeAnimation.characterOffset(index: index, maxOffset: 0.5)
            XCTAssertGreaterThanOrEqual(offset, 0)
            XCTAssertLessThanOrEqual(offset, 0.5)
        }
    }

    func testCharacterOffsetVariesByIndex() {
        // Not all indices should collapse to the same value.
        let values = Set((0..<20).map { SongMarqueeAnimation.characterOffset(index: $0) })
        XCTAssertGreaterThan(values.count, 1)
    }
}
