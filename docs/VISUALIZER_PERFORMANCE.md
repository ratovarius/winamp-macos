# Visualizer Smoothness & Performance — Problem and Solution

> Investigation and fixes for the FFT/visualizer "low refresh rate / not continuous"
> stutter on the `feature/metal-visualization` branch. Everything below was
> **measured**, not guessed, using lightweight diagnostics that remain in the code.

---

## 1. Symptom

While playing audio (most visibly a high-bitrate 320 kbps MP3), the in‑player FFT
spectrum and oscilloscope updated at a visibly low rate — "laggy", "not continuous",
clearly **< 10 Hz** — even though the player audio itself was fine.

## 2. How it was diagnosed

Rather than guessing, lightweight diagnostics measured each stage of the pipeline
independently.

> **Update:** the original `print`-based probes (which logged through a
> `DiagnosticLog` helper) have since been replaced by `os_signpost` instrumentation in
> [`Sources/Utilities/Instrumentation.swift`](../Sources/Utilities/Instrumentation.swift).
> The signposts below are general-purpose profiling hooks — they stay in the code and
> cost ~nothing when no trace is recording. Profile them in **Instruments** (Time
> Profiler + os_signpost templates), filtered by subsystem `com.winamp.macos`.

| Signpost | Category | Where | Measures |
|---|---|---|---|
| `fftAnalyze` (interval) | `Audio` | `FFTSpectrumAnalyzer.enqueue` | Per-buffer FFT CPU cost + analysis cadence (subsumes the old `[TAP]`/`[FRAMES-IN]`) |
| `frame` (interval) | `Visualization` | `MetalVisualizationRenderer.draw` | Per-frame CPU encode cost + draw rate (old `[DRAW-DIAG]`) |
| `gpu` (event) | `Visualization` | command-buffer completion | GPU execution time per frame, in microseconds |

The old `[EFF-DIAG]`/`[BAR-UPDATE]` probes were one-off validations of the hop-frame
playout fix (Root cause B); that behavior is now locked down by
`VisualizationPlayoutClockTests` instead.

**Run it (Instruments CLI):**
```bash
APP_BIN=$(find ~/Library/Developer/Xcode/DerivedData/Winamp-*/Build/Products/Debug/Winamp.app/Contents/MacOS/Winamp -maxdepth 0 | head -1)
xctrace record --template 'Time Profiler' --launch "$APP_BIN" --output /tmp/winamp.trace
open /tmp/winamp.trace   # inspect the os_signpost + Time Profiler tracks
```
The `frame`/`fftAnalyze` interval durations and the `gpu` event values quantify
CPU and GPU cost; the Time Profiler track shows the main-thread call graph.

---

## 3. Root causes (three distinct problems)

The investigation uncovered **three independent issues**. The first two were found by
code review; the third (the actual perceived lag) was found by measurement.

### Root cause A — Metal correctness (tearing + invalid drawable use)

Found by review, fixed first. These did **not** cause the low refresh rate but were
real correctness bugs that would cause flicker/validation errors.

- **A1 — No GPU frame synchronization.** Per‑frame Metal buffers (spectrum, peaks,
  scope columns, waveform, uniforms) were a *single* shared buffer overwritten by the
  CPU while the GPU might still be reading the previous frame → intermittent tearing.
- **A2 — `framebufferOnly` drawable used as a blit destination.** The spectrum
  persistence path blitted into `drawable.texture`, which is invalid for a
  `framebufferOnly` drawable and can trip Metal validation / driver-dependent flicker.

**Solution**
- Triple‑buffered the per‑frame buffers via a `FrameBufferRing` (3 slots) in
  `MetalVisualizationPlugin.swift`, gated by a `DispatchSemaphore(value: 3)` in
  `MetalVisualizationView.swift` signaled from `commandBuffer.addCompletedHandler`.
- Replaced the illegal blit with a fullscreen **present render pass** using a new
  `copyFragment` shader (`Shaders/VisualizerShaders.metal`) + `copyPipeline`
  (`MetalVisualizationEngine.swift`). History persistence still blits between offscreen
  textures (valid).

**Verification:** ran under `MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=assert
MTL_SHADER_VALIDATION=1` → zero validation errors; the spectrum present path renders
every frame.

### Root cause B — Audio data only arrives at 10 Hz

**Measured:** `[TAP] frameLength=4800 sampleRate=48000 → 100 ms buffers, ~10 Hz`.

macOS pins `mainMixerNode` taps to ~100 ms buffers **regardless of the requested
`bufferSize`** (tested 256 and 1024 — both still delivered 4800‑frame buffers). The
analyzer published only the **last** FFT hop of each buffer, so the spectrum target
changed just ~10×/sec while the renderer drew at 60–120 Hz — the smoother just
stretched stale data → stepping.

Crucially, each 100 ms buffer already contains ~18–19 FFT *hop* frames of detail
(`hopSize = 256`) that were being discarded.

**Solution — intra-buffer "playout".** Publish **all** hop frames of each buffer with
an arrival timestamp + buffer duration, then have the display loop sample the
appropriate frame by elapsed wall‑clock time:

- `Sources/Visualization/VisualizationPlayoutClock.swift` — a **pure, unit-tested**
  function mapping `(now, batchArrival, frameCount, batchDuration) → frameIndex`,
  clamped (holds the newest frame if a follow-up buffer is late; a single-frame /
  zero-duration publish always returns the newest frame).
- `FFTSpectrumAnalyzer` collects every hop into `onSpectrumFrames(frames, batchDuration)`.
- `AudioFeatureBus` stores the frame batch under its lock and exposes `snapshot(at:)`,
  which paces frames out across the buffer's 100 ms.
- `AudioPlayer` wires `onSpectrumFrames → publishSpectrumFrames`; the renderer passes
  its frame `now` into `snapshot(at:)`.

**Measured result:** effective spectrum-change rate **10 Hz → ~100 Hz** (≈ every draw
now carries fresh data). Adds ~100 ms of inherent visual latency (fine for bars).

> Note: this fix covers the **spectrum**. The waveform/oscilloscope still reads the
> ring buffer directly and is a candidate for the same treatment (see Follow‑ups).

### Root cause C — SwiftUI render storms starving the main-thread Metal draw  ← the actual lag

Even after B, the 320 kbps file still showed ~3 Hz. Measurement proved the renderer
itself was throttled:

- `[DRAW-DIAG] drawRate = 3.2 Hz` (vs 107 Hz with a short title), `[EFF-DIAG] 120/120
  draws changed` (playout fine — there were simply too few draws), CPU **110 %**.
- `sample` showed the main thread saturated by **SwiftUI view‑graph work**
  (`AttributeGraph`, `ViewGraphRootValueUpdater.render`, generic‑metadata instantiation),
  not audio or Metal.

`MTKView.draw(in:)` runs on the **main thread** (CVDisplayLink). Any main‑thread
SwiftUI churn directly starves the visualizer. Two sources were found:

**C1 — Song‑title marquee (`AnimatedSongDisplay`).** All four display modes ran a
`Canvas` inside `TimelineView(.animation, minimumInterval: 0.03)` that mutated `@State`
(e.g. `scrollOffset -= 0.3`) **every frame via `Task { @MainActor }`**, invalidating
the whole window's view graph ~33×/sec, and re‑measured text each frame. It only
triggered when the title was long enough to **scroll** — which is why a short startup
title looked fine but a real 320 kbps title stuttered.

**C2 — Playlist (`PlaylistView`).** Its footer showed the elapsed time
(`audioPlayer.currentTime`). Because a legacy `ObservableObject` re‑renders **every**
observing view on **any** `@Published` change, that 10 Hz tick invalidated the entire
`PlaylistView.body` — re‑running its `filteredTracks` + `groupedTracks` (O(n log n))
over the whole list 10×/sec.

**Solution**
- Rewrote `AnimatedSongDisplay` to be **purely time-based**: a single `@State
  animationEpoch` (reset only on track/mode change); every mode derives its offset/phase
  from `TimelineView`'s `context.date` via the pure, unit‑tested
  `Sources/Views/Player/SongMarqueeAnimation.swift`. No `Task`-mutates-`@State`, no
  per‑frame state writes. Scroll is now also frame‑rate‑independent. Visual behavior is
  unchanged (per `AGENTS.md` Winamp fidelity).
- Isolated the playlist clock into a tiny `PlaylistElapsedTimeLabel` subview that owns
  the `audioPlayer` dependency, and **removed** `@EnvironmentObject audioPlayer` from
  `PlaylistView` (that label was its only use). Now only the small label re‑renders at
  10 Hz; the list does not.

---

## 4. Results (measured, steady state, playlist open + playing)

| Metric | Before | After |
|---|---|---|
| Visualizer draw rate | **3.2 Hz** | **103–110 Hz** |
| Effective spectrum-change rate | ~10 Hz | ~100 Hz |
| Process CPU | **~110 %** | **~47 %** |
| Main-thread hot path | marquee + playlist render storms | clean |
| Metal validation errors | (latent) | none |

---

## 5. Why "just use another thread" isn't the fix

- **Metadata/format/ReplayGain reads are already off the main thread** (`Track.load`
  uses async `AVURLAsset`; `AudioPlayer.loadTrack` runs on its background `audioQueue`).
- **SwiftUI view rendering must run on the main thread** — that's a framework rule, not
  a choice. The visualizer's `MTKView.draw` is also main‑thread by design. The correct
  fix is to **stop forcing redundant main‑thread work** (the render storms), which is
  exactly what root cause C addresses.

---

## 6. Files changed

**New**
- `Sources/Visualization/VisualizationPlayoutClock.swift` (+ tests)
- `Sources/Views/Player/SongMarqueeAnimation.swift` (+ tests)
- `Sources/Utilities/Instrumentation.swift` (os_signpost profiling hooks)

**Modified**
- `Sources/Visualization/MetalVisualizationView.swift` — frame semaphore (A1),
  present render pass (A2), `snapshot(at:)` playout, `frame`/`gpu` signposts
- `Sources/Visualization/MetalVisualizationPlugin.swift` — `FrameBufferRing` (A1),
  `copyPipeline` accessor
- `Sources/Visualization/MetalVisualizationEngine.swift` — `copyPipeline` (A2)
- `Sources/Shaders/VisualizerShaders.metal` — `copyFragment` (A2)
- `Sources/Audio/AudioFeatureBus.swift` — store/pace hop frames
- `Sources/Audio/FFTSpectrumAnalyzer.swift` — publish all hop frames, `fftAnalyze` signpost
- `Sources/AudioPlayer.swift` — wire `onSpectrumFrames`
- `Sources/Views/Player/AnimatedSongDisplay.swift` — time-based marquee (C1)
- `Sources/PlaylistView.swift` — isolate elapsed-time label (C2)

## 7. Tests added
- `Tests/WinampTests/VisualizationPlayoutClockTests.swift` — pacing math
- `Tests/WinampTests/SongMarqueeAnimationTests.swift` — all four marquee modes + helpers

## 8. Follow-ups (not yet done)
- Apply the same intra‑buffer playout to the **waveform/oscilloscope** (needs a larger
  ring + time‑advancing read cursor).
- **Pause the `MTKView`** (`isPaused = true`) when nothing is playing and the smoother
  has decayed, to cut idle GPU/CPU.
- Optionally memoize `PlaylistView`'s filter/group into `@State` for very large
  libraries (no longer in the steady‑state hot path, but matters during restore).
