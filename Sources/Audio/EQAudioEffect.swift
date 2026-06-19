import AVFoundation

/// The classic Winamp 10-band equalizer as a graph effect: a preamp mixer feeding a
/// parametric `AVAudioUnitEQ`.
///
/// Owning the EQ DSP *policy* here — bit-perfect passthrough when flat/disabled, the
/// dB→linear preamp mapping, band configuration — keeps it unit-testable in isolation
/// without standing up an `AudioPlayer` or a running engine.
///
/// Only touched on the owning ``AudioGraph``'s serial audio queue; `@unchecked Sendable`
/// reflects that single-queue discipline, not node thread-safety.
final class EQAudioEffect: AudioEffectUnit, @unchecked Sendable {
    let identifier = "winamp.eq"

    /// Preamp gain stage. Upstream connects here.
    let preamp = AVAudioMixerNode()
    /// Parametric EQ. Feeds the next stage.
    let eq: AVAudioUnitEQ

    var inputNode: AVAudioNode {
        self.preamp
    }

    var outputNode: AVAudioNode {
        self.eq
    }

    init(bandCount: Int = WinampEQBands.bandCount) {
        self.eq = AVAudioUnitEQ(numberOfBands: bandCount)
        self.configureBands()
    }

    /// Programs each parametric band with its Winamp center frequency and bandwidth.
    private func configureBands() {
        for (index, frequency) in WinampEQBands.centerFrequenciesHz.enumerated() where index < self.eq.bands.count {
            let band = self.eq.bands[index]
            band.frequency = frequency
            band.bandwidth = WinampEQBands.bandwidthsOctaves[index]
            band.bypass = false
            band.filterType = .parametric
            band.gain = 0
        }
    }

    func attach(to engine: AVAudioEngine) {
        engine.attach(self.preamp)
        engine.attach(self.eq)
        engine.connect(self.preamp, to: self.eq, format: nil)
    }

    /// Applies full EQ settings. Engages bit-perfect passthrough — bypassing the EQ node
    /// and pinning the preamp to exact unity — when the EQ is disabled or effectively
    /// flat, so samples pass through untouched rather than round-tripping the filters at
    /// "0 dB". Returns the linear preamp gain actually applied (for diagnostics).
    @discardableResult
    func apply(_ settings: EQSettings) -> Float {
        let flat = Self.isEffectivelyFlat(settings)
        let bypass = !settings.eqEnabled || flat
        self.eq.bypass = bypass
        let linearGain = (bypass && flat) ? 1.0 : Self.linearGain(fromDecibels: settings.preampGainDB)
        self.preamp.outputVolume = linearGain
        for (index, gain) in settings.bandGainsDB.enumerated() where index < self.eq.bands.count {
            self.eq.bands[index].gain = gain
        }
        return linearGain
    }

    /// Sets a single band's gain directly (used by the AUTO path, which never returns to flat).
    func setBandGain(_ band: Int, decibels: Float) {
        guard band >= 0, band < self.eq.bands.count else { return }
        self.eq.bands[band].gain = decibels
    }

    /// Sets the preamp gain directly and returns the linear gain applied.
    @discardableResult
    func setPreampGain(decibels: Float) -> Float {
        let linearGain = Self.linearGain(fromDecibels: decibels)
        self.preamp.outputVolume = linearGain
        return linearGain
    }

    func setBypass(_ bypass: Bool) {
        self.eq.bypass = bypass
    }

    /// True when every band and the preamp sit within a hair of 0 dB — i.e. the EQ is a no-op.
    static func isEffectivelyFlat(_ settings: EQSettings, toleranceDB: Float = 0.05) -> Bool {
        guard abs(settings.preampGainDB) <= toleranceDB else { return false }
        return settings.bandGainsDB.allSatisfy { abs($0) <= toleranceDB }
    }

    /// dB → linear gain, clamped to the mixer's useful range (≈ −26 dB … +12 dB).
    static func linearGain(fromDecibels decibels: Float) -> Float {
        min(max(pow(10, decibels / 20), 0.05), 4)
    }

    /// Winamp AUTO preamp: the negative preamp (dB) that counteracts the summed positive band
    /// boost to limit clipping. Only boosts (positive band gains) contribute; the cut is capped
    /// at −9 dB so heavily-boosted curves don't go inaudibly quiet.
    static func autoPreampCompensationDB(forBandGainsDB bandGainsDB: [Float]) -> Float {
        let totalBoostDB = bandGainsDB.map { max(0, $0) }.reduce(0, +)
        return -min(totalBoostDB * 0.15, 9)
    }
}
