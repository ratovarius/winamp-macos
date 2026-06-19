import AVFoundation

/// A single insertable stage in the audio processing graph.
///
/// Conformers own one or more `AVAudioNode`s wired in series; the graph connects the
/// upstream signal into ``inputNode`` and reads the processed signal from ``outputNode``.
/// For a single-node effect, both return the same node.
///
/// Conformers are only ever touched on the owning ``AudioGraph``'s serial audio queue,
/// so concrete types are `@unchecked Sendable` under that single-queue discipline
/// (mirroring the rest of the audio path) — not because `AVAudioNode` is thread-safe.
protocol AudioEffectUnit: AnyObject {
    /// Stable identifier for lookup, ordering, and debugging.
    var identifier: String { get }

    /// The node the upstream stage connects into.
    var inputNode: AVAudioNode { get }

    /// The node this effect feeds to the next stage (or the graph destination).
    var outputNode: AVAudioNode { get }

    /// Attaches the owned node(s) to `engine` and wires any internal connections.
    /// Called once by the graph before it connects neighbouring stages.
    func attach(to engine: AVAudioEngine)
}
