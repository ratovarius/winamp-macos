@testable import Winamp
import XCTest

final class AudioFormatInfoTests: XCTestCase {
    func testReadWAVFixtureReportsSampleRate() throws {
        let url = try XCTUnwrap(
            Bundle(for: AudioFormatInfoTests.self).url(forResource: "short", withExtension: "wav")
        )
        let details = try XCTUnwrap(AudioFormatInfo.read(from: url))
        XCTAssertEqual(details.sampleRateHz, 44100, accuracy: 1)
        XCTAssertGreaterThan(details.bitrateKbps, 0)
        XCTAssertGreaterThan(details.channelCount, 0)
    }

    func testSampleRateDisplayKHz() {
        XCTAssertEqual(AudioFormatInfo.sampleRateDisplayKHz(44100), "44")
        XCTAssertEqual(AudioFormatInfo.sampleRateDisplayKHz(48000), "48")
        XCTAssertEqual(AudioFormatInfo.sampleRateDisplayKHz(96000), "96")
    }

    func testChannelLabel() {
        XCTAssertEqual(AudioFormatInfo.channelLabel(1), "mono")
        XCTAssertEqual(AudioFormatInfo.channelLabel(2), "stereo")
        XCTAssertEqual(AudioFormatInfo.channelLabel(6), "6ch")
    }

    func testChannelIndicators() {
        XCTAssertEqual(
            AudioFormatInfo.channelIndicators(for: 1),
            [AudioFormatInfo.ChannelIndicator(text: "mono", isActive: true)]
        )
        XCTAssertEqual(
            AudioFormatInfo.channelIndicators(for: 2),
            [
                AudioFormatInfo.ChannelIndicator(text: "mono", isActive: false),
                AudioFormatInfo.ChannelIndicator(text: "stereo", isActive: true),
            ]
        )
        XCTAssertEqual(
            AudioFormatInfo.channelIndicators(for: 6),
            [AudioFormatInfo.ChannelIndicator(text: "6ch", isActive: true)]
        )
    }
}
