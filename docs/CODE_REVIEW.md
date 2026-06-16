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
| I4 | `EqualizerView` graph: 80 `Path` allocations + 80 strokes per redraw | Important | ✅ Fixed |
| I5 | `PlaylistView` re‑filters/re‑groups on every body eval | Important | ✅ Fixed |
| S1 | `MTKView` never pauses when idle | Suggestion | ✅ Fixed |
| S2 | FFT tap allocates a fresh PCM buffer + arrays per callback | Suggestion | ⬜ Not done |
| S3 | Volume taper `p³` is aggressive | Suggestion | ℹ️ Design choice |
| S4 | Dead code: unused `@Published` arrays + `SpectrumBar` | Suggestion | ✅ Fixed |
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

### I4 — `EqualizerView` frequency graph redraw cost  ✅ Fixed
`Sources/EqualizerView.swift` (`FrequencyResponseGraph`) built **80 separate `Path`s and
80 `context.stroke` calls** (plus 160 Catmull‑Rom evals) on every redraw to color the
response curve by height — janky while dragging EQ sliders.
**Fix:** stroke the single Catmull‑Rom `curvePath` **once** with a vertical green→red
`LinearGradient` (`heightColorStops`, sampled from `WinampColors.levelColor` at its
0.45 / 0.72 break points). A vertical gradient at screen‑`y` evaluates to `level = 1 −
y/height`, reproducing the former per‑segment coloring pixel‑for‑pixel at 1 stroke
instead of 80. The now‑orphaned `CatmullRomSpline.point(at:)` evaluator was removed.
The band faders (`ClassicEQSlider`) still fill each full bar with its value‑based color.

### I5 — `PlaylistView` re‑filters/re‑groups on every body eval  ✅ Fixed
`filteredTracks` (enumerate + filter) and `groupedTracks` (`Dictionary(grouping:)` +
sort) were computed properties re‑run on every body evaluation — so selection, hover,
drag, and playback‑position changes all paid the O(n log n) grouping cost.
**Fix (two parts):**
1. Removed the 10 Hz invalidation trigger — the elapsed‑time label was extracted into
   `PlaylistElapsedTimeLabel` and `@EnvironmentObject audioPlayer` was removed from
   `PlaylistView`, so the list no longer recomputes 10×/sec.
2. Memoized the filter/group into `@State` (`filteredTracks`/`groupedTracks`), refreshed
   by `recomputeDerivedTracks()` only `.onAppear` and `.onChange(of: searchText)` /
   `.onChange(of: playlistManager.tracks)`. The pure work lives in static
   `filterTracks(_:searchText:)` / `groupTracks(_:)` helpers. `Track: Equatable` (by id),
   so the `tracks` change signal also catches reorders and edits. Unrelated re‑renders
   now read the cached arrays instead of recomputing.

---

## Suggestions / Minor

### S1 — `MTKView` never pauses when idle  ✅ Fixed
`view.isPaused = false` was always set, so when nothing was playing and the bars had
decayed, the mini visualizer kept redrawing a static frame at the display rate.
**Fix:** a pure, tested `Sources/Visualization/VisualizerIdleGate.swift` accumulates idle
time and, after a ~1 s hold (so the spectrum persistence afterglow finishes fading on
screen first), tells the renderer to pause. `MetalVisualizationRenderer.draw` treats a
frame as “active” while playing or while the smoothed bars still carry visible energy, and
sets `view.isPaused = true` after presenting the final decayed frame — **mini
visualizers only**; the continuously‑animating fullscreen Milkdrop plugin is excluded.
Resume is main‑thread and SwiftUI‑driven: `MetalVisualizationView` now takes `isPlaying`
(from `AudioPlayer`) and calls `renderer.resume(_:)` from `updateNSView` when playback
restarts. Cuts idle GPU/CPU/power to zero for the mini visualizer.

### S2 — FFT tap per‑callback allocations  ⬜ Not done
`FFTSpectrumAnalyzer` allocates a fresh `AVAudioPCMBuffer` + `memcpy` per callback and
per‑hop `[Float]` arrays. It's on a background queue (won't glitch audio/UI) but churns
memory. **Recommended:** reuse scratch buffers.

### S3 — Volume taper `p³`  ℹ️ Design choice
`volumeTaper` uses `p*p*p` (≈ −18 dB at the halfway point) — correct direction but
quite aggressive; the lower half of the fader feels very quiet. Consider `p²`/hybrid.
Not a bug.

### S4 — Dead code  ✅ Fixed
`AudioPlayer.spectrumData`, `AudioPlayer.waveformLeft`, `AudioPlayer.waveformRight`
(`@Published`) were unused once analysis began publishing only to `AudioFeatureBus`, and
`SpectrumBar` in `Sources/SpectrumView.swift` had no call sites.
**Fix:** removed all four (reference search confirmed zero usages beyond their
declarations). The visualization data now flows solely through `AudioFeatureBus`, which
the removal makes explicit.

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
| Extract pure idle/pause math for the visualizer (testable without GPU) | ✅ Done — `VisualizerIdleGate` + tests |
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
1. **S2** — reuse FFT scratch buffers (stop per‑callback allocations).
2. Testability: extract `VolumeModel`; inject a `Clock` into the renderer.
