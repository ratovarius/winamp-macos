# Architecture Review — Winamp macOS

> Whole-project architecture review (not a single PR/commit), assessing the codebase
> against four target qualities for a **professional, best-in-class audio player**:
> (1) a **modular** audio pipeline, (2) **excellent + performant** visualizations,
> (3) **fully automated testability**, and (4) **profiling** of the critical modules
> (audio core, visualization) for CPU / memory / GPU.
>
> Scope: `feature/metal-visualization` (the active line of development, ~10.3K LOC).
> Companion docs: [`CODE_REVIEW.md`](CODE_REVIEW.md) (bug-level review) and
> [`VISUALIZER_PERFORMANCE.md`](VISUALIZER_PERFORMANCE.md) (the measured perf fixes).

**Status legend:** ✅ Done · 🟡 Partially addressed · ⬜ Not yet started · ℹ️ Design note

---

## Verdict

The codebase is a **well-engineered enthusiast project with several genuinely
sophisticated parts** — the concurrency model, the FFT→display frame-pacing, and the
"DSP-as-pure-functions" discipline are above the bar for hobby projects and some
commercial ones. It is **not yet best-in-class for a professional, extensible audio
player**, and the gaps cluster in exactly the four target areas. None of the gaps are
deep rewrites: the foundations are sound; what's missing is a small number of *seams*
and *infrastructure*.

| Goal | Grade | One-line summary |
|---|---|---|
| 1. Modular audio pipeline | **C+ → B−** | **`AudioGraph` + `AudioEffectUnit` foundation landed** (EQ is the first unit; modules insert into an ordered chain). Remaining: `AudioRenderingEngine` seam + decompose the god object. |
| 2. Excellent + performant visualizations | **B+** | Performance engineering is excellent; the preset/extensibility system is the weak point. |
| 3. Fully automated testability | **C+ → B−** | ~177 good unit tests exist; **CI now runs them (P0 ✅)**. Views/render/window still untested. |
| 4. Profiling (CPU/mem/GPU) | **C → B−** | **`os_signpost` + GPU timing added (P0 ✅)**. MetricKit + memory instrumentation still open. |

---

## Goal 1 — Modularity of the audio pipeline  🟡 (foundation landed in P1)

> **Progress (2026-06-16, P1):** the hardcoded wiring below has been replaced by an
> [`AudioGraph`](../Sources/Audio/AudioGraph.swift) that connects an ordered list of
> [`AudioEffectUnit`](../Sources/Audio/AudioEffectUnit.swift)s
> (`source → effects → mainMixer`), with the EQ extracted as the first unit
> ([`EQAudioEffect`](../Sources/Audio/EQAudioEffect.swift)). Adding a DSP module is now
> `graph.insert(_:at:)` / `graph.append(_:)` — no hand-wiring. The EQ DSP *policy*
> (flat/disabled passthrough, dB→linear preamp) moved into `EQAudioEffect` and is unit
> tested in isolation. **Still open:** the `AudioRenderingEngine` seam and decomposing
> the rest of the `AudioPlayer` god object (transport / volume / remote-commands /
> now-playing). The original analysis below stands for that remaining work.

**The biggest architectural gap relative to the stated goal** ("possibility to add audio
modules to the pipeline").

The graph is built once, imperatively, hand-wired in
[`AudioPlayer.setupAudioEngine()`](../Sources/AudioPlayer.swift#L139-L170):

```
player → preamp → eq → mainMixer        (+ FFT tap on mainMixer)
```

To add a module (compressor, limiter, crossfeed/headphone DSP, resampler, a second EQ,
a VST-like effect), today you must:

1. Add another `nonisolated(unsafe) var someNode: AVAudioUnit?` field
   ([`AudioPlayer.swift#L60-L66`](../Sources/AudioPlayer.swift#L60-L66)),
2. Edit `setupAudioEngine()` to `attach` + re-`connect` the chain,
3. Thread its parameters/state through the god object by hand.

There is **no `AudioEffect`/`AudioNode` protocol**, no ordered insertable chain, no
per-effect bypass / wet-dry contract. The EQ is hardwired as a concrete
`AVAudioUnitEQ`; ReplayGain is applied as `playerNode.volume` rather than as a node; the
analysis tap is hardwired onto `mainMixerNode` inside the player.

Compounding this, [`AudioPlayer.swift`](../Sources/AudioPlayer.swift) is a **996-line god
object** owning transport, engine lifecycle, EQ, ReplayGain/volume,
`MPRemoteCommandCenter`, now-playing info, lyrics loading, the spectrum tap, the 10 Hz UI
timer, *and* ~10 `testing_` hooks. The "pipeline" is inseparable from transport and UI.

**Best-in-class target:** an `AudioGraph` that owns the `AVAudioEngine` and exposes an
ordered list of `AudioEffectUnit`. EQ becomes *one* unit; new modules implement the
protocol and are inserted without touching transport.

```swift
protocol AudioEffectUnit: AnyObject {
    var node: AVAudioNode { get }
    var isBypassed: Bool { get set }
    func attach(to engine: AVAudioEngine)
}

final class AudioGraph {
    func insert(_ unit: AudioEffectUnit, at index: Int)   // rewires neighbors
    func remove(_ unit: AudioEffectUnit)
    var tapPoint: AVAudioNode { get }                     // where the FFT tap lives
}
```

**Already good here (preserve):** the AVAudioEngine setup is clean; the bit-perfect
passthrough/bypass logic
([`applyEQSettings`](../Sources/AudioPlayer.swift#L222-L240)) is thoughtful; and the
**generation-ID race protection** (`loadGeneration` / `playbackGeneration`) for stale
loads/seeks is genuinely professional-grade.

---

## Goal 2 — Visualizations (looks + performance)  🟡

**The strongest area.** The performance engineering is real:

- Metal via `MTKView` delegate (vsync-aligned), **triple buffering** (`FrameBufferRing`)
  + `DispatchSemaphore(3)` GPU back-pressure
  ([`MetalVisualizationPlugin.swift#L34-L48`](../Sources/Visualization/MetalVisualizationPlugin.swift#L34-L48)).
- **Idle gating** to pause the render loop and save power when audio stops
  ([`VisualizerIdleGate.swift`](../Sources/Visualization/VisualizerIdleGate.swift)).
- **Frame pacing** solving the macOS "tap fires ~10 Hz but display is 60–120 Hz"
  mismatch by storing every FFT hop and playing them out by elapsed time
  ([`VisualizationPlayoutClock.swift`](../Sources/Visualization/VisualizationPlayoutClock.swift),
  documented in [`VISUALIZER_PERFORMANCE.md`](VISUALIZER_PERFORMANCE.md)). Most
  implementations get this wrong.
- Pure, unit-tested smoother + peak-tracker; pipeline-state caching behind an unfair lock.
- A real plugin seam exists:
  [`MetalVisualizationPlugin`](../Sources/Visualization/MetalVisualizationPlugin.swift#L22-L31).

**Where it falls short of "best-in-class extensible visuals":**

| # | Issue | Severity | Where |
|---|---|---|---|
| V1 | Multi-pass persistence/composite orchestration lives in the **renderer**, not behind the plugin protocol — a new visualization needing different passes requires engine surgery. | 🟡 Medium | [`MetalVisualizationView.swift`](../Sources/Visualization/MetalVisualizationView.swift) `drawSpectrumWithPeakPersistence` |
| V2 | Fullscreen "Milkdrop" presets are hardcoded in the shader as `preset % 4`, yet `VisualizationPreset` declares **11** cases — **7 are unreachable**. No procedural/scriptable preset system. | 🟡 Medium | [`VisualizerShaders.metal`](../Sources/Shaders/VisualizerShaders.metal) ~L348, [`VisualizationPreset.swift`](../Sources/Views/Visualizer/VisualizationPreset.swift) |
| V3 | `VizUniforms` is **duplicated** in Swift + Metal with no compile-time layout check — a future field reorder silently corrupts rendering. | 🟡 Medium | [`MetalVisualizationPlugin.swift#L4-L15`](../Sources/Visualization/MetalVisualizationPlugin.swift#L4-L15) |
| V4 | **Silent pipeline-compile failures**: `makePipeline` returns `try? … → nil` with no log; a bad shader just skips frames. | 🟡 Medium | [`MetalVisualizationEngine.swift#L108-L117`](../Sources/Visualization/MetalVisualizationEngine.swift#L108-L117) |
| V5 | Minor per-frame allocations on the render path (waveform `readResampled`, uniforms struct). | 🟢 Low | `WaveformRingBuffer`, `MetalPipelineProvider.updateFloatBuffer` |

All are incremental fixes except V2, which deserves a real design (data-driven presets
or a shader-graph / uniform-table approach).

---

## Goal 3 — Fully automated testability  🟡 (CI gap closed in P0)

**The unit-test foundation is good; the *automation* was the broken part.**

- ~177 tests across 38 files thoroughly cover the *pure* layers: FFT, auto-leveler, peak
  tracker, playout clock, ring buffer, parsers (M3U/LRC/metadata/EQF), playlist
  manager/state/bookmarks, volume model, EQ bands, window snapping/docking. A genuinely
  strong base reflecting deliberate "extract pure function → test it" discipline.
- Good DI seams exist:
  [`AudioPlaybackControlling`](../Sources/AudioPlaybackControlling.swift) +
  [`MockAudioPlayer`](../Tests/WinampTests/MockAudioPlayer.swift), plus injectable
  `featureBus`, `engine`, and `VisualizationClock`.

**Was-critical, now fixed (P0 ✅):** CI did **not** run the tests —
[`.github/workflows/build.yml`](../.github/workflows/build.yml) only built the app, made
a DMG, and cut a release. The suite only ran when someone remembered to run it locally.
A `test` job now runs `scripts/run-tests.sh`, and `build` has `needs: test`, so failing
tests block the release.

**Remaining testability debt:**

| # | Issue | Severity |
|---|---|---|
| T1 | `AudioPlayer` carries **~10 `testing_` methods in the production type** ([`AudioPlayer.swift#L818-L905`](../Sources/AudioPlayer.swift#L818-L905)) — a symptom of the type being too coupled to mock cleanly. Extracting `AudioRenderingEngine` removes most. | 🟡 Medium |
| T2 | Untested: all SwiftUI views, the Metal `draw` loop, window-drag management, and the actual playback lifecycle (only state transitions are tested). | 🟡 Medium |
| T3 | Pervasive singletons (`AudioFeatureBus.shared`, etc.) carry state *between* tests, undermining isolation. | 🟢 Low |

---

## Goal 4 — Profiling (CPU / memory / GPU)  🟡 (signposts added in P0)

There's a real **measurement culture** here
([`VISUALIZER_PERFORMANCE.md`](VISUALIZER_PERFORMANCE.md) shows rigorous, measured
debugging) — the gap was that the **tooling was ad-hoc** (`print` + `sample`), not
Instruments-grade.

**Fixed in P0 ✅:** a centralized `os_signpost` layer
([`Instrumentation.swift`](../Sources/Utilities/Instrumentation.swift)) with `Audio` and
`Visualization` categories under subsystem `com.winamp.macos`:

- `frame` interval around per-frame CPU encoding in the renderer.
- `gpu` event emitting `gpuEndTime − gpuStartTime` (µs) from the command-buffer
  completion handler.
- `fftAnalyze` interval around per-buffer FFT work in the analyzer.

The retired `print`-based probes (`[DRAW-DIAG]`, `[EFF-DIAG]`, `[BAR-UPDATE]`,
`[TAP-DIAG]`, `[FRAMES-IN]`) and the now-dead `DiagnosticLog.swift` were removed. These
signposts cost ~nothing when no trace is recording and surface directly in Instruments.

**Remaining profiling debt:**

| # | Issue | Severity |
|---|---|---|
| P-A | **No MetricKit** subscriber (no field CPU/memory/hang/launch aggregation). | 🟡 Medium |
| P-B | **No memory instrumentation** — allocations-per-frame on the render path (V5) are not tracked. | 🟢 Low |
| P-C | `WinampMetrics` is a **misnomer** — it's UI layout constants, not performance metrics. Potential naming confusion. | 🟢 Low |

---

## Cross-cutting strengths (keep these)

- **Concurrency model is carefully reasoned**: a single serial `audioQueue` owns the
  engine, `@MainActor` isolates UI, generation IDs guard races, and `nonisolated(unsafe)`
  is used *deliberately under a single-queue discipline* rather than carelessly.
- **Clear module folders** (`Audio/`, `Visualization/`, `Playlist/`, `Views/`,
  `Utilities/`) with boundaries documented in [`AGENTS.md`](../AGENTS.md).
- **Lock-protected feature bus** with a clean snapshot API
  ([`AudioFeatureBus.swift`](../Sources/Audio/AudioFeatureBus.swift)).

---

## Prioritized roadmap

### P0 — cheap, high-impact  ✅ Done (2026-06-16)

1. ✅ **Add a test job to CI** (`xcodebuild test` via `scripts/run-tests.sh`) gating the
   release. Unblocks goal 3's automation.
2. ✅ **`os_signpost` instrumentation layer + GPU command-buffer timing**; retired the
   `print`-based probes. Unblocks goal 4.

### P1 — the modularity foundation (goal 1)  🟡 In progress

3. 🟡 **Insertable effect chain.** ✅ `AudioGraph` + `AudioEffectUnit` with EQ as the
   first unit (`EQAudioEffect`), EQ policy unit-tested. ⬜ Still extract an
   **`AudioRenderingEngine` protocol** (mockable engine seam) to remove the `testing_*`
   leakage from `AudioPlayer` (T1).
4. ⬜ **Decompose `AudioPlayer`** into Transport / Graph / Volume+ReplayGain /
   RemoteCommands / NowPlaying collaborators.

### P2 — visualization extensibility (goal 2)  ⬜

5. **Move multi-pass orchestration behind the plugin protocol** (V1), add a
   **data-driven preset system** (fix the `% 4` ceiling, V2), add a **compile-time
   `VizUniforms` layout assertion** (V3) + **logging on pipeline-compile failure** (V4).

### P3 — testability depth (goal 3)  ⬜

6. Add **snapshot tests** for the retro chrome and a small **render-smoke harness** for
   the Metal path (T2); reduce singleton state-bleed between tests (T3).

### P4 — profiling depth (goal 4)  ⬜

7. Add a **MetricKit** subscriber (P-A) and optional allocation tracking on the render
   path (P-B).

---

## Change log

| Date | Change |
|---|---|
| 2026-06-16 | Initial whole-project architecture review. P0 implemented: CI test gating + `os_signpost`/GPU-timing instrumentation; `print` probes and `DiagnosticLog` retired. |
| 2026-06-16 | P1 (foundation): introduced `AudioGraph` + `AudioEffectUnit`; extracted the EQ as `EQAudioEffect` (policy unit-tested); `AudioPlayer` now builds its pipeline from an ordered effect chain instead of hardcoded wiring. |
