# AGENTS.md

> Guidance for AI coding agents (Claude Code, GitHub Copilot, Cursor, etc.) working on this codebase.
> Read this file before making any changes. It describes the project intent, architecture, known technical debt, coding conventions, and the roadmap this fork is pursuing.

---

## Project Overview

This is a personal fork of [`mbrukman/winamp-macos`](https://github.com/mbrukman/winamp-macos), itself a tribute/clone of the legendary Winamp media player, written in Swift for macOS.

**Fork goal:** evolve the upstream proof-of-concept into a production-quality, modern macOS music player that preserves the Winamp UX spirit while using best-in-class audio engineering, Metal-accelerated visualizations, and a clean, maintainable Swift codebase.

Target users are music collectors and audiophiles who remember Winamp fondly and want that workflow — compact floating window, playlist, EQ, visualizer — but with lossless audio quality, modern codec support, and a native macOS feel.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI + AppKit interop where needed |
| Audio engine | AVFoundation / AVAudioEngine |
| DSP / EQ | AVAudioUnitEQ (10-band parametric) |
| Visualizations | Metal |
| Build system | Xcode 15+ primary; SPM as secondary |
| Min deployment | macOS 13.0 (Ventura) |
| License | MIT |

---

## Module Map & Boundaries

`Sources/` is a single SPM/Xcode module. It documents each area's **responsibility and the rules to respect**:

- **Top-level `Sources/`** — the app shell and primary models/views: `WinampApp` (`@main` + menus),
  `ContentView` (root view + AppKit window setup), `AudioPlayer` (AVAudioEngine + EQ + media keys),
  `PlaylistManager`, `Track`, and the parsers (`M3UParser`, `TrackMetadataParser`).
- **`Audio/`** — DSP & analysis (FFT, EQ bands, feature bus, ring buffer, auto-leveler). Pure
  signal/data code; **keep SwiftUI/AppKit out of it** so it stays testable and reusable.
- **`Playlist/`** — persistence & file I/O (state store, M3U file service, security-scoped
  bookmarks). UI talks to this only through `PlaylistManager`, not these types directly.
- **`Views/Player`, `Views/Components`** — the retro player chrome. New UI here **must match the
  classic Winamp 2.x aesthetic** (see Architecture Principles). `Views/Components` is the home for
  reusable chrome primitives (bevels, sliders, 7-segment display, search field).
- **`Views/Visualizer`, `Visualization/`, `Shaders/`** — the Metal-backed visualizer and `.metal`
  shaders. Heavy/optional; must degrade gracefully when the visualizer window is closed.
- **`Utilities/`** — cross-cutting helpers (colors, metrics, UI scale, typography, FS helpers).
- **`Development/`** — dev-only conveniences (e.g. session persistence). **Never required at
  runtime**; guard so production paths don't depend on it.
- **`AudioPlaybackControlling`** — the protocol abstracting the player so tests can inject a mock.
  Prefer depending on this protocol over the concrete `AudioPlayer` in new code.

Supporting dirs: `Tests/` (XCTest `WinampTests` + generated `Fixtures/`), `scripts/` (test runner,
`uv` fixture generation, `shoot.sh` UI screenshots), `Resources/` (asset catalog, audio, fonts),
`Winamp.xcodeproj/` (primary build), `Package.swift` (secondary SPM build, no asset catalog).

---

## Architecture Principles

**Winamp UX fidelity.**
The compact-player aesthetic is intentional. Do not introduce full-window redesigns. New UI panels should match the existing retro aesthetic.

---

## Coding Conventions

- **Swift formatting:** follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- **Comments:** explain *why*, not *what*. Code should be self-documenting; comments clarify intent, not mechanics.

### Git commits

- **Never add `Co-authored-by:` trailers** (or variants like `Co-Authored-By:`) to commit messages — not for Cursor, Claude, Copilot, or any other AI tool. Commits should list only the human author.
- **Never pass `--trailer`** on `git commit` (e.g. `--trailer "Co-authored-by: Cursor <cursoragent@cursor.com>"`). Use plain `git commit -m` or `git commit -F` only.

---

## Build & Test

### Quick build (command line)
```bash
./build.sh --run        # debug build + launch
./build.sh --release    # release build
```

### Xcode
Open `Winamp.xcodeproj`, select the `Winamp` scheme, target `My Mac`, then `⌘R`.

### Iterating on UI (see the rendered app)
```bash
./scripts/shoot.sh            # build + relaunch + screenshot each window
./scripts/shoot.sh --no-build # skip the build; just relaunch + screenshot (fast)
```
Screenshots land in `/tmp/winamp_shot0.png`, `…shot1.png`, etc. Captures **by window ID**
(`screencapture -l<id>`) so it grabs the real window pixels even when occluded — no need to
fight window focus. Essential for the Winamp-fidelity work: edit SwiftUI → `shoot.sh` → compare
to the reference skin → repeat.

### Clean build
```bash
xcodebuild -project Winamp.xcodeproj -scheme Winamp clean
# or in Xcode: ⌘⇧K
```

### Running tests
Use the project script — it generates the required fixtures first, then runs the suite:
```bash
./scripts/run-tests.sh
```
This wraps:
```bash
./scripts/generate-fixtures.sh   # builds Tests/Fixtures (sample.m3u, short.wav)
xcodebuild test -project Winamp.xcodeproj -scheme Winamp \
    -destination 'platform=macOS,arch=arm64' ONLY_ACTIVE_ARCH=YES
```
`scripts/run-tests.sh` picks `arm64` or `x86_64` via `uname -m` so Intel Macs work without editing the script.
Running `xcodebuild test` directly without generating fixtures first will fail the fixture-dependent suites (M3U, WAV) — those are missing-file errors, not real regressions.

### Formatting & linting
The repo ships `.swiftformat` and `.swiftlint.yml` configs with wrapper scripts:
```bash
./scripts/format-swift.sh   # apply SwiftFormat
./scripts/lint-swift.sh     # run SwiftLint
```
Run these before committing if the tools are installed; do not hand-fight their style choices.

### Python (`scripts/`)

Fixture generation and any other Python in this repo run through **[uv](https://docs.astral.sh/uv/)** — not bare `python` / `pip`.

- **Agents:** always use `uv` from `scripts/` (e.g. `cd scripts && uv run …`). Do not invoke `python3`, `pip install`, or create ad-hoc virtualenvs.
- **Entry point:** `./scripts/generate-fixtures.sh` runs `uv sync` then `uv run generate-fixtures`.
- **Add dependencies** in `scripts/pyproject.toml` and lock with `uv lock` (commit `scripts/uv.lock`).

```bash
cd scripts
uv sync
uv run generate-fixtures
uv run python -c "import winamp_fixtures"   # ad-hoc checks
```

### Common pitfalls
- SPM (`swift build`) will **not** include the asset catalog — use Xcode for anything touching `Resources/`.
- If you get `Sandbox: deny file-read-data`, that is expected for files outside user selection — the app uses entitlements for user-selected file access only.

---

## Upstream Attribution

This project is forked from [`mbrukman/winamp-macos`](https://github.com/mbrukman/winamp-macos), originally by Matt Greenwood, MIT licensed. The upstream project was itself a tribute to the original Winamp by Nullsoft. 