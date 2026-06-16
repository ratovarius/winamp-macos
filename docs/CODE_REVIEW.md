# Code Review — `feature/metal-visualization`

> Comprehensive review focused on **performance, audio quality, UI smoothness/flicker,
> and testability**, with the current status of each finding.
> Scope: the `feature/metal-visualization` branch (reworks most of the app vs `main`).

**Status legend:** ✅ Fixed · 🟡 Partially addressed · ⬜ Not yet done · ℹ️ Design note

---

## Summary

| # | Finding | Severity | Status |
|---|---|---|---|
| C1 | Metal: no in‑flight frame synchronization (tearing) | Critical | ✅ Fixed |
| C2 | Metal: `framebufferOnly` drawable used as blit destination | Critical | ✅ Fixed |
| B  | Spectrum data only published at ~10 Hz (intra‑buffer detail discarded) | Critical* | ✅ Fixed |
| I1 | Debug `print()` in audio/EQ/volume hot paths | Important | ✅ Fixed |
| I2 | Main‑thread coupling between SwiftUI and the Metal draw | Important | ✅ Fixed |
| I3 | `AnimatedSongDisplay`: per‑frame `@State` churn + frame‑rate‑dependent motion | Important | ✅ Fixed |
| I4 | `EqualizerView` graph: 80 `Path` allocations + 80 strokes per redraw | Important | ⬜ Not done |
| I5 | `PlaylistView` re‑filters/re‑groups on every body eval | Important | 🟡 Partial |
| S1 | `MTKView` never pauses when idle | Suggestion | ⬜ Not done |
| S2 | FFT tap allocates a fresh PCM buffer + arrays per callback | Suggestion | ⬜ Not done |
| S3 | Volume taper `p³` is aggressive | Suggestion | ℹ️ Design choice |
| S4 | Dead code: unused `@Published` arrays + `SpectrumBar` | Suggestion | ⬜ Not done |
| S5 | Per‑button `Task.sleep(80ms)`, per‑digit `Canvas` | Minor | ⬜ Not done (low value) |

\* B was discovered during measurement, not the original static review; it is the data‑rate
half of the "low refresh rate" report.

---

## Critical

### C1 — Metal: no in‑flight frame synchronization  ✅ Fixed
Per‑frame GPU buffers were a single shared buffer the CPU could overwrite while the GPU
still read the previous frame → tearing/flicker.
**Fix:** `FrameBufferRing` (3 slots) in `Sources/Visualization/MetalVisualizationPlugin.swift`
rotated per frame, gated by `DispatchSemaphore(value: 3)` in
`Sources/Visualization/MetalVisualizationView.swift` (signaled in
`addCompletedHandler`). Verified under Metal validation layer.

### C2 — `framebufferOnly` drawable used as a blit destination  ✅ Fixed
The spectrum persistence path blitted into the drawable, which is invalid for a
`framebufferOnly` drawable.
**Fix:** present via a fullscreen render pass using a new `copyFragment` shader +
`copyPipeline` (`Shaders/VisualizerShaders.metal`, `MetalVisualizationEngine.swift`).
Offscreen‑to‑offscreen history blit (valid) retained. Zero validation errors under
`MTL_DEBUG_LAYER_ERROR_MODE=assert`.

### B — Spectrum published at ~10 Hz  ✅ Fixed
macOS pins the `mainMixerNode` tap to ~100 ms buffers; only the last FFT hop was
published, so the spectrum target changed ~10×/sec. **Fix:** publish all hop frames per
buffer and pace them out by elapsed time via the pure, tested
`Sources/Visualization/VisualizationPlayoutClock.swift`. See
`docs/VISUALIZER_PERFORMANCE.md` for details. Effective rate ~10 Hz → ~100 Hz.

---

## Important

### I1 — Debug `print()` in audio/EQ/volume hot paths  ✅ Fixed
Five `print(String(format: "[AUDIO] …"))` calls ran on every EQ/volume change —
including **per EQ‑band drag tick** — in `Sources/AudioPlayer.swift`
(`applyEQSettings`, `applyPlayerVolume`, `recomputeNormalizationGain`, `setEQBand`,
`applyPreampGainToEngine`). `print` is synchronous unbuffered stdio with eager
`String(format:)`. The FFT analysis callback also eagerly built a debug string per
tap buffer via `SpectrumAnalyzerDebugProbe`.
**Fix:** deleted all five `print` calls (and the now‑dead dB/freq locals computed
only for them). The debug probe's `context` is now an `@autoclosure`, so the string
(and its `log10`) is only built after the probe's enabled + ~1 Hz throttle guards
pass — not on every tap callback.

### I2 — Main‑thread coupling between SwiftUI and the Metal draw  ✅ Fixed
`MTKView.draw` runs on the main thread, so heavy main‑thread SwiftUI work starves the
visualizer. Beyond eliminating the two render storms (I3, I5), the ~10 Hz playback
position was split off `AudioPlayer` onto a dedicated `PlaybackClock: ObservableObject`
(`Sources/AudioPlayer.swift`). `AudioPlayer.currentTime` now forwards to it, so call
sites are unchanged, but the tick only invalidates the small readouts that observe the
clock — `PlayerTimeReadout`/`PlayerSeekBar` (`MainPlayerView`), `ShadeTimeReadout`
(`ShadeView`), and `PlaylistElapsedTimeLabel` (`PlaylistView`) — instead of every view
that observes the player. The clock is injected alongside the player in both window
environments (`WinampApp`, `WinampPanelWindowManager`).
ℹ️ The structural fact (Metal draws on main) remains by design; keeping main‑thread
work cheap is the ongoing rule.

### I3 — `AnimatedSongDisplay` per‑frame `@State` churn  ✅ Fixed
All four modes mutated `@State` every frame from inside a `Canvas`/`TimelineView`,
invalidating the whole window's view graph ~33×/sec (the primary cause of the lag) and
advancing by fixed pixels‑per‑frame (frame‑rate‑dependent judder).
**Fix:** rewrote to derive everything from `TimelineView`'s `context.date` + a single
`animationEpoch`, with pure math extracted to
`Sources/Views/Player/SongMarqueeAnimation.swift` (17 unit tests). No `@State` writes
during render; frame‑rate‑independent; identical look.

### I4 — `EqualizerView` frequency graph redraw cost  ⬜ Not done
`Sources/EqualizerView.swift` (`FrequencyResponseGraph`, ~line 334) builds **80 separate
`Path`s and 80 `context.stroke` calls** (plus two Catmull‑Rom evals each) on every
redraw — janky while dragging EQ sliders.
**Recommended:** build one `Path` and stroke once (or a few color‑banded sub‑paths).

### I5 — `PlaylistView` re‑filters/re‑groups on every body eval  🟡 Partial
`filteredTracks` (enumerate + filter) and `groupedTracks` (`Dictionary(grouping:)` +
sort) are computed properties re‑run on every body evaluation.
**Done:** removed the 10 Hz invalidation trigger — the elapsed‑time label was extracted
into `PlaylistElapsedTimeLabel` and `@EnvironmentObject audioPlayer` was removed from
`PlaylistView`, so the list no longer recomputes 10×/sec. Verified gone from the CPU
sample in steady state.
**Still recommended (not done):** memoize the filter/group into `@State` updated on
`searchText` / track‑list change, to avoid O(n log n) work for very large libraries
during legitimate re‑renders (e.g. restore).

---

## Suggestions / Minor

### S1 — `MTKView` never pauses when idle  ⬜ Not done
`view.isPaused = false` always (`MetalVisualizationView.swift`). When nothing is playing
and the smoother has decayed, the loop still runs at display rate.
**Recommended:** pause when idle, resume on playback — cuts idle GPU/CPU/power.

### S2 — FFT tap per‑callback allocations  ⬜ Not done
`FFTSpectrumAnalyzer` allocates a fresh `AVAudioPCMBuffer` + `memcpy` per callback and
per‑hop `[Float]` arrays. It's on a background queue (won't glitch audio/UI) but churns
memory. **Recommended:** reuse scratch buffers.

### S3 — Volume taper `p³`  ℹ️ Design choice
`volumeTaper` uses `p*p*p` (≈ −18 dB at the halfway point) — correct direction but
quite aggressive; the lower half of the fader feels very quiet. Consider `p²`/hybrid.
Not a bug.

### S4 — Dead code  ⬜ Not done
`AudioPlayer.spectrumData`, `AudioPlayer.waveformLeft`, `AudioPlayer.waveformRight`
(`@Published`, ~lines 22–24) appear unused now that analysis publishes only to
`AudioFeatureBus`; `SpectrumBar` in `Sources/SpectrumView.swift` is unused. Removing
them clarifies the data flow.

### S5 — Press feedback / seven‑segment  ⬜ Not done (low value)
Per‑button `Task.sleep(80ms)` for press feedback and per‑digit `SevenSegmentDisplay`
`Canvas` are low‑impact; leave unless profiling flags them.

---

## Testability — status

Existing suite is strong (~35 files: FFT, ring buffer, smoother, peak tracker,
autoleveler, ReplayGain, EQ parsing, docking/snap geometry, the
`AudioPlaybackControlling` + `MockAudioPlayer` seam).

| Recommendation | Status |
|---|---|
| Extract pure pacing math for the visualizer (testable without GPU) | ✅ Done — `VisualizationPlayoutClock` + tests |
| Extract the marquee animation into a pure, testable state machine | ✅ Done — `SongMarqueeAnimation` + tests |
| Extract a pure `VolumeModel` (`taper`, `taper × ReplayGain`) from `AudioPlayer` | ⬜ Not done |
| Inject a `Clock` into `MetalVisualizationRenderer` (remove direct `CACurrentMediaTime()`) | ⬜ Not done |
| `AudioRenderingEngine` protocol seam over `AVAudioEngine`/nodes (mock EQ wiring) | ⬜ Not done |
| Extract `PanelDragGeometry` from `WinampPanelWindowManager` | ⬜ Not done |

---

## Strengths (preserve)
- Correct decoupling of audio analysis from rendering via `AudioFeatureBus` +
  display‑link `MTKView`; time‑based attack/release smoothing and peak tracking.
- Bit‑perfect EQ passthrough when flat, ReplayGain, perceptual volume taper,
  generation‑counter guards against stale loads/seeks.
- Genuinely strong, fast unit‑test suite with clean protocol seams and fixtures.

---

## Recommended next actions
1. **I4** — single‑`Path` EQ graph (smooths slider dragging).
2. **I5** — memoize playlist filter/group (large‑library polish).
3. **S1** — pause the visualizer when idle (power).
4. **S4** — delete dead `@Published` arrays + `SpectrumBar`.
5. Testability: extract `VolumeModel`; inject a `Clock` into the renderer.
