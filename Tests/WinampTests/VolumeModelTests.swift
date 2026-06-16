import XCTest

@testable import Winamp

final class VolumeModelTests: XCTestCase {
    func testTaperEndpoints() {
        XCTAssertEqual(VolumeModel.taper(0), 0, accuracy: 0.0001)
        XCTAssertEqual(VolumeModel.taper(1), 1, accuracy: 0.0001)
    }

    func testTaperIsCubic() {
        XCTAssertEqual(VolumeModel.taper(0.5), 0.125, accuracy: 0.0001)
        XCTAssertEqual(VolumeModel.taper(0.8), 0.512, accuracy: 0.0001)
    }

    func testTaperClampsOutOfRangePositions() {
        XCTAssertEqual(VolumeModel.taper(-0.5), 0, accuracy: 0.0001)
        XCTAssertEqual(VolumeModel.taper(1.5), 1, accuracy: 0.0001)
    }

    func testAppliedGainCombinesTaperAndNormalization() {
        // taper(0.5) == 0.125; × 2.0 normalization == 0.25
        XCTAssertEqual(
            VolumeModel.appliedGain(position: 0.5, normalizationGain: 2.0),
            0.25,
            accuracy: 0.0001
        )
    }

    func testAppliedGainClampsToMax() {
        // taper(1.0) == 1.0; × 8.0 would be 8.0 but the ceiling is maxAppliedGain.
        XCTAssertEqual(
            VolumeModel.appliedGain(position: 1.0, normalizationGain: 8.0),
            VolumeModel.maxAppliedGain,
            accuracy: 0.0001
        )
    }

    func testAppliedGainNeverNegative() {
        XCTAssertEqual(
            VolumeModel.appliedGain(position: -1, normalizationGain: -5),
            0,
            accuracy: 0.0001
        )
    }

    func testAppliedGainWithNormalizationDisabledIgnoresReplayGain() {
        let replayGain = ReplayGain(
            trackGainDB: -6, albumGainDB: nil, trackPeak: nil, albumPeak: nil)
        XCTAssertEqual(
            VolumeModel.appliedGain(
                position: 0.5,
                normalizationEnabled: false,
                replayGain: replayGain,
                preferAlbum: false
            ),
            VolumeModel.taper(0.5),
            accuracy: 0.0001
        )
    }

    func testAppliedGainWithNormalizationEnabledAppliesReplayGain() {
        let replayGain = ReplayGain(
            trackGainDB: -6, albumGainDB: nil, trackPeak: nil, albumPeak: nil)
        let expected = VolumeModel.taper(0.5) * replayGain.normalizationGain(preferAlbum: false)
        XCTAssertEqual(
            VolumeModel.appliedGain(
                position: 0.5,
                normalizationEnabled: true,
                replayGain: replayGain,
                preferAlbum: false
            ),
            expected,
            accuracy: 0.0001
        )
    }
}
