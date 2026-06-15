# Webamp UI Fidelity Reference

This document captures findings from reviewing **[Webamp](https://github.com/captbaritone/webamp)** — the open-source Winamp 2.x recreation ([webamp.org](https://webamp.org/)) — as a layout and behavior reference for this native macOS fork.

Webamp is **not** a runtime dependency. We use it as a spec for geometry, spacing, skin coordinates, and classic Winamp behavior. The app remains SwiftUI + AppKit with our own `WinampMetrics`, `WinampSkinSprites`, and procedural chrome.

---

## How Webamp achieves fidelity

Webamp treats classic Winamp 2.x as a **fixed-pixel skin system**:

| Layer | Role | Key files (Webamp repo) |
|---|---|---|
| Constants | Canonical window and track sizes | `packages/webamp/js/constants.ts` |
| Sprite atlas | BMP sheets → named sprites with x/y/w/h | `packages/webamp/js/skinSprites.ts` |
| Layout CSS | Absolute positions of every control | `packages/webamp/css/main-window.css`, `equalizer-window.css`, `playlist-window.css` |
| Runtime sizing | Shade toggle, double-size, playlist resize | `packages/webamp/js/selectors.ts`, `actionCreators/windows.ts` |
| Default skin | Ground-truth bitmaps | `packages/webamp/assets/skins/base-2.91.wsz` |

Fidelity comes from reverse-engineering the bundled **Base 2.91** `.wsz` into a hand-maintained coordinate table plus absolute CSS — validated against the original skin, not parsed from a separate PDF spec.

External references Webamp cites: [skinspecs.pdf](https://github.com/captbaritone/webamp), Skinner's Atlas, Sacrat tutorials, and [docs.webamp.org/features/skins](https://docs.webamp.org/features/skins).

---

## Canonical dimensions (Base 2.91 / Webamp)

### Window grid

| Element | Width | Height | Notes |
|---|---|---|---|
| Main window (normal) | 275 | 116 | Fixed |
| Main window (shade) | 275 | 14 | Collapses to title strip only |
| Equalizer (normal) | 275 | 116 | Same as main |
| Equalizer (shade) | 275 | 14 | |
| Playlist (default size) | 275 | 116 | ~4 visible tracks |
| Stacked trio (main+EQ+PL) | 275 | 348 | 116 × 3 |
| Title bar | 275 | 14 | |
| Playlist row | — | 13 | `TRACK_HEIGHT` |
| Playlist resize step | +25 | +29 | Per `extraWidth` / `extraHeight` |

### Main player sub-controls

| Control | Size | Position (approx.) | Source |
|---|---|---|---|
| Window buttons (shade/min/close) | 9 × 9 | x = 244, 254, 264 | `main-window.css` |
| Clutter bar | 8 × 43 | (10, 22) | `skinSprites.ts` |
| Marquee | 154 × 6 | (111, 24) | `main-window.css` |
| Visualizer (normal) | 76 × 16 | — | `Vis.tsx`, `skinSprites.ts` |
| Visualizer (shade) | 38 × 5 | (79, 5) | `main-window.css` `.shade` |
| Time digits | 9 × 13 | x = 9, 21, 39, 51 | `NUMBERS.BMP` |
| Marquee glyphs | 5 × 6 | `TEXT.BMP` | `CHARACTER_WIDTH = 5` |
| Position bar track | 248 × 10 | — | `POSBAR` sprites |
| Position bar thumb | 29 × 10 | — | `POSBAR` sprites |
| Volume track | 68 × 13 | — | `VOLUME` sprites |
| Balance track | 38 × 13 | — | `BALANCE` sprites |
| Transport buttons | 23 × 18 | y = 88 | `CBUTTONS` (next is 22 × 18) |
| EQ / PL toggles | 23 × 12 | — | `MAIN` sheet |
| Shuffle / repeat | 47 × 15 / 28 × 15 | — | `SHUFREP` |
| Shade transport | 7–10 wide | x ≈ 169–215, y = 2 | `main-window.css` `.shade` |
| Shade position thumb | 3 × 7 | (226, 4) | `main-window.css` |
| Shade mini-time | 25 × 6 | (127, 4) | `mini-time.css` |

### Equalizer

| Element | Value |
|---|---|
| ON button | 26 × 12 at (14, 18) |
| AUTO button | 32 × 12 at (40, 18) |
| PRESETS button | 44 × 12 at (217, 18) |
| EQ graph | 113 × 19 at (86, 17) |
| Band sliders | x = 78, 96, 114 … 240, y = 38 |
| Band frequencies (Hz) | 60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000 |
| Slider thumb | 11 × 11 |
| Thumb sprite grid | 15 px wide × 65 px tall (28 steps) |

### Playlist chrome

| Element | Size |
|---|---|
| Top bar | 20 px tall (corners 25 px, title center 100 px) |
| Bottom bar | 38 px tall |
| Side tiles | left 12 px, right 20 px |
| Track row | 13 px height, 9 px font, 0.5 px letter-spacing |
| Default list area | 58 px (~4 tracks at default size) |

### Default colors (`baseSkin.json`)

**Playlist (PLEDIT.TXT):**

- Normal text: `#00FF00`
- Current text: `#FFFFFF`
- Background: `#000000`
- Selected background: `#0000FF` (classic blue bar)
- Font: Arial (bitmap in skin; we use JetBrains Mono / seven-segment)

**VISCOLOR:** 24 RGB entries for visualizer and EQ graph dots (indices 0–1 = background/foreground).

---

## Webamp rendering techniques worth mirroring

1. **Fixed 275 × 116 grid** — non-negotiable for classic proportions; double-size is a 2× CSS transform.
2. **Sprite atlas as single source of truth** — every button state (normal / selected / depressed) has explicit BMP rects.
3. **Absolute layout** — flexbox is avoided for main/EQ; each control has pixel x/y.
4. **Shade = height collapse** — `#main-window.shade { height: 14px }` with controls repositioned onto the title strip.
5. **Playlist 9-slice tiles** — `PLEDIT` BMP stretched in 25 × 29 px resize segments.
6. **Bitmap typography** — LCD time and marquee use sprite digits, not vector fonts; time blinks on pause.
7. **Pixelated scaling** — `image-rendering: pixelated`, `box-sizing: content-box`.
8. **Window docking graph** — toggling shade or resizing playlist preserves edge-snapped multi-window layout (`resizeUtils.ts`).

---

## This fork: current state vs classic

### Infrastructure already in place

| Component | Path | Status |
|---|---|---|
| Layout constants | `Sources/Utilities/WinampMetrics.swift` | Partial — uses 450 px width |
| UI scale (100–200%) | `Sources/Utilities/WinampUIScale.swift` | ✓ |
| Classic palette | `Sources/WinampColors.swift` | ✓ PLEDIT-aligned |
| BMP sprite coords | `Sources/WinampSkinSprites.swift` | ✓ 275 px coords; underused in views |
| Skin bitmap helpers | `WinampSkinButton`, `SkinSpriteView` | Implemented, not wired to main UI |
| Chrome primitives | `Sources/Views/Components/WinampClassicChrome.swift` | Procedural bevels + vector glyphs |
| Seven-segment time | `MainPlayerView` | ✓ (custom sizes, not 9 × 13) |
| EQ bands | `WinampEQBands` / `EqualizerView` | ✓ frequencies match Webamp `BANDS` |
| Volume/balance frames | `ModernSlider.swift` | ✓ 68 × 13 / 38 × 13 |

### Dimension comparison

| Element | Webamp / classic | winamp-macos (today) |
|---|---|---|
| Panel width | 275 | **450** (`WinampMetrics.panelWidth`) |
| Main player body height | 116 (incl. title) | **160** body + 14 title |
| Title bar | 14 | 14 ✓ |
| Shade mode | 14 px bar | Custom row below title (~50 px content) |
| Transport buttons | 23 × 18 | **31 × 24** in `MainPlayerView` |
| EQ/PL toggles | 23 × 12 | **24 × 20** (`ModernToggleButtonWithLight`) |
| Playlist row | 13 px | **19 px** |
| Position bar | 248 × 10 flat + thumb | Rounded rectangle, ~20 px tall |
| Visualizer | 76 × 16 | ~185 × 42 block |
| Typography | 5 × 6 / 9 × 13 bitmap | JetBrains Mono 8–14 pt, system fonts in places |
| Skin sprites in live UI | Bitmap everywhere | Mostly vector / SwiftUI-drawn |
| `ShadeView` scaling | N/A | **No `winampUIScale`** |
| Default window size | 275 × 348 stacked | 450 × 500 (`WinampApp.swift`) |

### Structural differences

**Webamp main player** is a single 275 px strip: clutter bar, marquee, visualizer, kbps/kHz, time, sliders, and transport in one absolute grid.

**Our main player** (`MainPlayerView.swift`) uses a **two-column layout** — black LCD/spectrum block on the left (~185 px), metadata and sliders on the right — inside a 450 px panel. This is an intentional modernization but breaks pixel parity with classic Winamp.

**Our shade mode** (`ShadeView.swift`) adds a content row under the title bar with emoji transport (⏮ ▶ ⏸), system monospaced time, and a 50 × 20 mini visualizer. Classic shade keeps everything on the 14 px title strip.

### Documentation drift

`USAGE.md` and `CHANGES.md` still reference **275 px** width; code uses **450 px** via `WinampMetrics` and `WinampUIScale.basePanelWidth`.

---

## Adoptable ideas (prioritized)

### High impact

1. **Rebaseline `WinampMetrics` to 275 × 116** — use `WinampUIScale` for accessibility instead of a wider logical panel.
2. **Port `main-window.css` positions** — add `MainPlayerLayout` constants (transport y=88, volume at (107,57), etc.) and replace magic numbers in `MainPlayerView.swift`.
3. **Rewrite shade mode as 14 px collapse** — align `ShadeView` with Webamp shade rules: mini-viz (79,5), transport (169–215), position (226,4), mini-time (127,4).
4. **Wire `WinampSkinSprites` into live views** — transport, EQ/PL toggles, window buttons via `WinampSkinButton` where bitmaps win over vectors.
5. **Playlist row height 13 px** — match `TRACK_HEIGHT`; adopt PLEDIT tile chrome (top 20, bottom 38, sides 12/20).

### Medium impact

6. **Bitmap LED time and marquee** — 9 × 13 digits, 5 × 6 scroll text; pause blink (`MiniTime.tsx` behavior).
7. **EQ layout from `equalizer-window.css`** — graph at (86,17), bands every 18 px from x=78; title sub-bar 14 px not 16 px.
8. **Visualizer 76 × 16** — use VISCOLOR palette; shade variant 38 × 5.
9. **Window docking graph** — preserve snapped positions when shade toggles or playlist resizes.
10. **Reduce rounded corners** — classic skin uses sharp rects; audit `cornerRadius` in main player and shade.

### Reference / tooling

11. **Regression loop** — [webamp.org](https://webamp.org/) vs `./scripts/shoot.sh` at matching scale.
12. **Expand `WinampSkinSprites`** — port remaining regions from `skinSprites.ts` (TITLEBAR shade, PLAYPAUS, EQMAIN, PLEDIT tiles).

---

## Key Webamp source files

When implementing or reviewing UI changes, consult these first:

```
packages/webamp/js/constants.ts          # WINDOW_WIDTH, TRACK_HEIGHT, BANDS, resize increments
packages/webamp/js/skinSprites.ts        # Full BMP coordinate atlas
packages/webamp/js/baseSkin.json         # PLEDIT colors, VISCOLOR, tiny EQ assets
packages/webamp/js/selectors.ts          # Shade height, playlist visible-row math, stacking
packages/webamp/js/resizeUtils.ts        # Window graph snap on resize/shade
packages/webamp/js/components/Vis.tsx    # Visualizer dimensions
packages/webamp/js/components/MiniTime.tsx
packages/webamp/js/components/EqualizerWindow/Band.tsx
packages/webamp/css/main-window.css
packages/webamp/css/equalizer-window.css
packages/webamp/css/playlist-window.css
packages/webamp/css/webamp.css            # pixelated, doubled, box-sizing
packages/webamp/assets/skins/base-2.91.wsz
```

### Corresponding files in this repo

```
Sources/Utilities/WinampMetrics.swift
Sources/Utilities/WinampUIScale.swift
Sources/WinampSkinSprites.swift
Sources/WinampColors.swift
Sources/Views/Player/MainPlayerView.swift
Sources/Views/Player/ShadeView.swift
Sources/Views/Player/PlayerWindowChrome.swift
Sources/Views/Components/WinampClassicChrome.swift
Sources/Views/Components/ModernSlider.swift
Sources/EqualizerView.swift
Sources/PlaylistView.swift
scripts/shoot.sh                          # screenshot regression
```

---

## Development workflow

1. Open [webamp.org](https://webamp.org/) for the target panel (main, EQ, playlist, shade).
2. Build and capture this app:
   ```bash
   ./scripts/shoot.sh
   ```
   Screenshots land in `/tmp/winamp_shot0.png`, `winamp_shot1.png`, etc.
3. Compare at the same UI scale (View → UI Scale in our app; 100% Webamp in browser).
4. Adjust `WinampMetrics`, `WinampSkinSprites`, and view-specific layout enums.
5. Re-run `shoot.sh` until the target region matches.

For behavior checks (shade toggle, double-click title bar, playlist resize snapping), interact with Webamp manually or use the Cursor IDE Browser MCP against webamp.org.

---

## Philosophy

This fork is a **native macOS music player** that preserves Winamp's compact floating-window workflow — not a Webamp port. Webamp informs:

- **Geometry** — 275 px grid, 14 px rows, sprite sizes
- **Behavior** — shade collapse, window docking, LED blink, playlist resize quantization
- **Colors** — PLEDIT and VISCOLOR defaults

We keep SwiftUI/AppKit, lossless codecs, Metal visualizations, media keys, and macOS integrations. Implementation choices (procedural chrome vs bitmap skins, 450 px modernization vs strict 275 px) remain explicit trade-offs documented in the table above.

---

## Attribution

- [Webamp](https://github.com/captbaritone/webamp) by Jordan Eldredge et al., MIT License.
- Original Winamp by Nullsoft.
- This fork: [`ratovarius/winamp-macos`](https://github.com/ratovarius/winamp-macos), forked from [`mbrukman/winamp-macos`](https://github.com/mbrukman/winamp-macos).
