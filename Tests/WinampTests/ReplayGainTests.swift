import XCTest
@testable import Winamp

final class ReplayGainTests: XCTestCase {
    func testEmptyGainReturnsUnity() {
        let rg = ReplayGain()
        XCTAssertTrue(rg.isEmpty)
        XCTAssertEqual(rg.normalizationGain(preferAlbum: false), 1.0, accuracy: 0.0001)
    }

    func testTrackGainConvertsToLinear() {
        // -6 dB → ~0.501 linear
        let rg = ReplayGain(trackGainDB: -6, albumGainDB: nil, trackPeak: nil, albumPeak: nil)
        XCTAssertEqual(rg.normalizationGain(preferAlbum: false), pow(10, -6.0 / 20), accuracy: 0.001)
    }

    func testPeakLimitsBoostToAvoidClipping() {
        // +12 dB gain would clip a track that already peaks at 0.9; cap at 1/0.9.
        let rg = ReplayGain(trackGainDB: 12, albumGainDB: nil, trackPeak: 0.9, albumPeak: nil)
        let gain = rg.normalizationGain(preferAlbum: false)
        XCTAssertEqual(gain, 1.0 / 0.9, accuracy: 0.001)
        XCTAssertLessThanOrEqual(gain * 0.9, 1.0001, "Normalized peak must not exceed full scale")
    }

    func testPreferAlbumUsesAlbumGain() {
        let rg = ReplayGain(trackGainDB: -3, albumGainDB: -9, trackPeak: nil, albumPeak: nil)
        XCTAssertEqual(rg.normalizationGain(preferAlbum: true), pow(10, -9.0 / 20), accuracy: 0.001)
        XCTAssertEqual(rg.normalizationGain(preferAlbum: false), pow(10, -3.0 / 20), accuracy: 0.001)
    }

    func testFallsBackWhenPreferredModeMissing() {
        let trackOnly = ReplayGain(trackGainDB: -5, albumGainDB: nil, trackPeak: nil, albumPeak: nil)
        // Prefer album, but only track gain exists → use track gain.
        XCTAssertEqual(trackOnly.normalizationGain(preferAlbum: true), pow(10, -5.0 / 20), accuracy: 0.001)
    }

    func testGainClampedToReasonableRange() {
        let huge = ReplayGain(trackGainDB: 99, albumGainDB: nil, trackPeak: nil, albumPeak: nil)
        XCTAssertLessThanOrEqual(huge.normalizationGain(preferAlbum: false), 4.0)
    }
}
