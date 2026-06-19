import AVFoundation
@testable import Winamp
import XCTest

final class EQAudioEffectTests: XCTestCase {
    // MARK: - Pure policy: linear gain mapping

    func testLinearGainUnityAtZeroDB() {
        XCTAssertEqual(EQAudioEffect.linearGain(fromDecibels: 0), 1.0, accuracy: 0.0001)
    }

    func testLinearGainMapsPositiveDB() {
        // +6 dB ≈ ×1.995
        XCTAssertEqual(EQAudioEffect.linearGain(fromDecibels: 6), 1.995, accuracy: 0.01)
    }

    func testLinearGainClampsCeilingAndFloor() {
        // +20 dB would be ×10, clamped to ×4; −100 dB clamped to the 0.05 floor.
        XCTAssertEqual(EQAudioEffect.linearGain(fromDecibels: 20), 4.0, accuracy: 0.0001)
        XCTAssertEqual(EQAudioEffect.linearGain(fromDecibels: -100), 0.05, accuracy: 0.0001)
    }

    // MARK: - Pure policy: flatness detection

    func testFlatWhenAllZero() {
        XCTAssertTrue(EQAudioEffect.isEffectivelyFlat(.default))
    }

    func testFlatWithinTolerance() {
        let settings = EQSettings(
            bandGainsDB: Array(repeating: 0.04, count: 10),
            preampGainDB: 0.04,
            eqEnabled: true,
            autoEnabled: false
        )
        XCTAssertTrue(EQAudioEffect.isEffectivelyFlat(settings))
    }

    func testNotFlatWhenBandBoosted() {
        var settings = EQSettings.default
        settings.bandGainsDB[3] = 6
        XCTAssertFalse(EQAudioEffect.isEffectivelyFlat(settings))
    }

    func testNotFlatWhenPreampOffset() {
        var settings = EQSettings.default
        settings.preampGainDB = 3
        XCTAssertFalse(EQAudioEffect.isEffectivelyFlat(settings))
    }

    // MARK: - Band configuration

    func testConfigureBandsUsesWinampFrequencies() {
        let effect = EQAudioEffect()
        XCTAssertEqual(effect.eq.bands.count, WinampEQBands.bandCount)
        for (index, frequency) in WinampEQBands.centerFrequenciesHz.enumerated() {
            XCTAssertEqual(effect.eq.bands[index].frequency, frequency, accuracy: 0.001)
            XCTAssertEqual(effect.eq.bands[index].filterType, .parametric)
            XCTAssertFalse(effect.eq.bands[index].bypass)
        }
    }

    // MARK: - apply()

    func testApplyFlatEnabledEngagesBypassAndUnityPreamp() {
        let effect = EQAudioEffect()
        let gain = effect.apply(.default)
        XCTAssertTrue(effect.eq.bypass)
        XCTAssertEqual(gain, 1.0, accuracy: 0.0001)
    }

    func testApplyBoostedEnabledDisengagesBypassAndSetsBands() {
        let effect = EQAudioEffect()
        var settings = EQSettings.default
        settings.bandGainsDB[0] = 6
        settings.bandGainsDB[9] = -3
        let gain = effect.apply(settings)
        XCTAssertFalse(effect.eq.bypass)
        XCTAssertEqual(effect.eq.bands[0].gain, 6, accuracy: 0.001)
        XCTAssertEqual(effect.eq.bands[9].gain, -3, accuracy: 0.001)
        // Preamp at 0 dB → unity even when the bands are active.
        XCTAssertEqual(gain, 1.0, accuracy: 0.0001)
    }

    func testApplyWithPreampReturnsLinearGain() {
        let effect = EQAudioEffect()
        var settings = EQSettings.default
        settings.bandGainsDB[0] = 6 // non-flat so the preamp is honoured
        settings.preampGainDB = 6
        let gain = effect.apply(settings)
        XCTAssertFalse(effect.eq.bypass)
        XCTAssertEqual(gain, EQAudioEffect.linearGain(fromDecibels: 6), accuracy: 0.0001)
    }

    func testApplyDisabledBypassesEQ() {
        let effect = EQAudioEffect()
        var settings = EQSettings.default
        settings.eqEnabled = false
        XCTAssertEqual(effect.apply(settings), 1.0, accuracy: 0.0001)
        XCTAssertTrue(effect.eq.bypass)
    }

    // MARK: - Direct setters

    func testSetBandGainAppliesAndIgnoresOutOfRange() {
        let effect = EQAudioEffect()
        effect.setBandGain(2, decibels: 5)
        XCTAssertEqual(effect.eq.bands[2].gain, 5, accuracy: 0.001)
        // Out-of-range indices are no-ops rather than crashes.
        effect.setBandGain(-1, decibels: 9)
        effect.setBandGain(99, decibels: 9)
    }

    func testSetPreampGainReturnsLinearGain() {
        let effect = EQAudioEffect()
        XCTAssertEqual(effect.setPreampGain(decibels: 6), EQAudioEffect.linearGain(fromDecibels: 6), accuracy: 0.0001)
    }

    func testSetBypassTogglesEQ() {
        let effect = EQAudioEffect()
        effect.setBypass(true)
        XCTAssertTrue(effect.eq.bypass)
        effect.setBypass(false)
        XCTAssertFalse(effect.eq.bypass)
    }

    // MARK: - Graph contract

    func testInputAndOutputNodesAreDistinct() {
        let effect = EQAudioEffect()
        XCTAssertTrue(effect.inputNode === effect.preamp)
        XCTAssertTrue(effect.outputNode === effect.eq)
    }

    // MARK: - AUTO preamp compensation

    func testAutoPreampZeroWhenNoBoost() {
        XCTAssertEqual(EQAudioEffect.autoPreampCompensationDB(forBandGainsDB: Array(repeating: 0, count: 10)), 0, accuracy: 0.0001)
    }

    func testAutoPreampIgnoresCuts() {
        // Only positive boosts drive the compensation; negative band gains contribute nothing.
        let cutsOnly = [Float](repeating: -6, count: 10)
        XCTAssertEqual(EQAudioEffect.autoPreampCompensationDB(forBandGainsDB: cutsOnly), 0, accuracy: 0.0001)
    }

    func testAutoPreampScalesWithSummedBoost() {
        // Two +6 dB bands → 12 dB summed boost → −12 × 0.15 = −1.8 dB.
        var bands = [Float](repeating: 0, count: 10)
        bands[0] = 6
        bands[1] = 6
        XCTAssertEqual(EQAudioEffect.autoPreampCompensationDB(forBandGainsDB: bands), -1.8, accuracy: 0.0001)
    }

    func testAutoPreampCapsAtMinusNineDB() {
        // 10 × +12 dB = 120 dB summed boost → −18 dB uncapped, clamped to −9 dB.
        let maxed = [Float](repeating: 12, count: 10)
        XCTAssertEqual(EQAudioEffect.autoPreampCompensationDB(forBandGainsDB: maxed), -9, accuracy: 0.0001)
    }
}
