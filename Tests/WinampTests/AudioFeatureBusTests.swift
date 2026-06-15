import XCTest

@testable import Winamp

final class AudioFeatureBusTests: XCTestCase {
    func testPublishSpectrumAndSnapshot() {
        let bus = AudioFeatureBus.shared
        let spectrum = Array((0 ..< AudioFeatures.spectrumBandCount).map { Float($0) / 20 })

        bus.publishSpectrum(spectrum, isPlaying: true)

        let snapshot = bus.snapshot()
        XCTAssertEqual(snapshot.spectrum.count, AudioFeatures.spectrumBandCount)
        XCTAssertEqual(snapshot.waveformLeft.count, AudioFeatures.waveformSampleCount)
        XCTAssertEqual(snapshot.waveformRight.count, AudioFeatures.waveformSampleCount)
        XCTAssertTrue(snapshot.isPlaying)
        XCTAssertGreaterThan(snapshot.bassEnergy, 0)
    }

    func testSetPlayingFalse() {
        let bus = AudioFeatureBus.shared
        bus.publishSpectrum(Array(repeating: 0.8, count: AudioFeatures.spectrumBandCount), isPlaying: true)
        bus.setPlaying(false)

        let (_, isPlaying) = bus.spectrumSnapshot()
        XCTAssertFalse(isPlaying)
    }
}
