import AVFoundation

/// Owns the `AVAudioEngine` and an ordered chain of ``AudioEffectUnit``s wired between a
/// source player node and the engine's main mixer:
///
///     source → effects[0] → … → effects[n] → mainMixer → output
///
/// Adding a DSP module to the pipeline is ``insert(_:at:)`` — the chain rewires itself,
/// so there is no hand-edited node wiring as the pipeline grows.
///
/// The engine is not thread-safe: every method must be called on the owning player's
/// serial audio queue. `@unchecked Sendable` reflects that single-queue discipline.
final class AudioGraph: @unchecked Sendable {
    let engine: AVAudioEngine
    /// Signal source the chain starts from. Owned and attached by the graph.
    let source: AVAudioPlayerNode
    private(set) var effects: [AudioEffectUnit] = []

    /// Node the analysis tap (FFT / visualizer) reads from — the graph's final mix.
    var tapPoint: AVAudioNode {
        self.engine.mainMixerNode
    }

    var isRunning: Bool {
        self.engine.isRunning
    }

    init(engine: AVAudioEngine = AVAudioEngine(), source: AVAudioPlayerNode = AVAudioPlayerNode()) {
        self.engine = engine
        self.source = source
        self.engine.attach(self.source)
    }

    /// Attaches and connects the given effects in order, replacing any existing chain.
    func build(effects: [AudioEffectUnit]) {
        self.effects = effects
        for effect in effects {
            effect.attach(to: self.engine)
        }
        self.reconnect()
    }

    /// Inserts an effect at `index` (clamped) and rewires the chain.
    func insert(_ effect: AudioEffectUnit, at index: Int) {
        let clamped = min(max(index, 0), self.effects.count)
        effect.attach(to: self.engine)
        self.effects.insert(effect, at: clamped)
        self.reconnect()
    }

    /// Appends an effect to the end of the chain (before the main mixer).
    func append(_ effect: AudioEffectUnit) {
        self.insert(effect, at: self.effects.count)
    }

    /// Removes the effect with the given identifier (if present) and rewires the chain.
    @discardableResult
    func removeEffect(identifier: String) -> AudioEffectUnit? {
        guard let index = self.effects.firstIndex(where: { $0.identifier == identifier }) else {
            return nil
        }
        let effect = self.effects.remove(at: index)
        self.engine.disconnectNodeOutput(effect.outputNode)
        self.engine.disconnectNodeInput(effect.inputNode)
        self.reconnect()
        return effect
    }

    func effect(identifier: String) -> AudioEffectUnit? {
        self.effects.first { $0.identifier == identifier }
    }

    func start() throws {
        try self.engine.start()
    }

    /// Tears down the external connections of the chain and re-wires
    /// source → effects → mainMixer in the current order.
    ///
    /// Disconnecting an effect's *input* side and the *output* side of the previous stage
    /// leaves each effect's internal wiring (e.g. the EQ's preamp→eq link made in
    /// `attach(to:)`) intact, so a rebuild never has to know an effect's internals.
    private func reconnect() {
        self.engine.disconnectNodeOutput(self.source)
        for effect in self.effects {
            self.engine.disconnectNodeOutput(effect.outputNode)
            self.engine.disconnectNodeInput(effect.inputNode)
        }

        var upstream: AVAudioNode = self.source
        for effect in self.effects {
            self.engine.connect(upstream, to: effect.inputNode, format: nil)
            upstream = effect.outputNode
        }
        self.engine.connect(upstream, to: self.engine.mainMixerNode, format: nil)
    }
}
