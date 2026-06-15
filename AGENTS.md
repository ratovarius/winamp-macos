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

## Repository Structure

```
winamp-macos/
├── Sources/                       # All Swift source files (single SPM target)
│   ├── WinampApp.swift            # @main App entry point + menu commands
│   ├── ContentView.swift          # Root view; hosts player + Milkdrop window
│   ├── Views/Player/MainPlayerView.swift  # Main player window chrome + transport
│   ├── Views/Visualizer/            # MilkdropCanvas, MilkdropVisualizerView
│   ├── PlaylistView.swift         # Playlist panel (drag-to-reorder + file drop)
│   ├── PlaylistManager.swift      # Playlist model (order, shuffle, repeat)
│   ├── EqualizerView.swift        # 10-band EQ panel UI
│   ├── AudioPlayer.swift          # AVAudioEngine wrapper + EQ + Now Playing/media keys
│   ├── AudioPlaybackControlling.swift  # Protocol abstracting the player (for tests/mocks)
│   ├── SpectrumView.swift         # Spectrum analyzer (real FFT bars + time-domain oscilloscope)
│   ├── M3UParser.swift            # .m3u/.m3u8 playlist parsing
│   ├── TrackMetadataParser.swift  # Track tag/metadata extraction
│   ├── LyricsParser.swift         # .lrc lyrics parsing
│   ├── Track.swift                # Track model
│   ├── WinampColors.swift         # Palette constants
│   └── WinampSkinSprites.swift    # Bundled sprite/skin assets
├── Tests/                         # XCTest target (WinampTests) + Fixtures
├── scripts/                       # Test runner + fixture generation (`uv` Python env; see Build & Test)
├── Resources/                     # Asset catalog, bundled audio, skin assets
├── Winamp.xcodeproj/              # Xcode project (primary build)
├── Package.swift                  # SPM manifest (secondary, no asset catalog)
├── build.sh                       # Convenience wrapper around xcodebuild
├── bump-version.sh
├── create-dmg.sh
├── BUILDING.md                    # Full build instructions
├── USAGE.md                       # End-user usage guide
├── CHANGES.md                     # Changelog
└── AGENTS.md                      # ← This file
```

> **Note for agents:** `Sources/` is a single SPM/Xcode target. Top-level files and subfolders (`Audio/`, `Playlist/`, `Views/`, etc.) are all part of the same module. When adding new files, place them under `Sources/` and reference them in the Xcode project and `Package.swift` if needed.

---

## Architecture Principles

**Winamp UX fidelity.**
The compact-player aesthetic is intentional. Do not introduce full-window redesigns or streaming-service UI patterns. New UI panels should match the existing retro aesthetic.

---

## Coding Conventions

- **Swift formatting:** follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- **File naming:** one major type per file, named after the type. e.g. `PlaylistController.swift` for `class PlaylistController`.
- **Access control:** default to `private` or `internal`. Only `public` what's needed across module boundaries (currently: nothing is).
- **`@State` vs. `@StateObject`:** use `@State` for value types, `@StateObject` for reference-type models that should survive view identity changes.
- **Prefer value types** (structs, enums) for models. Use classes only when identity or shared mutable state is genuinely required.
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
./scripts/generate-fixtures.sh   # builds Tests/Fixtures (sample.m3u, sample.lrc, short.wav)
xcodebuild test -project Winamp.xcodeproj -scheme Winamp \
    -destination 'platform=macOS,arch=arm64' ONLY_ACTIVE_ARCH=YES
```
`scripts/run-tests.sh` picks `arm64` or `x86_64` via `uname -m` so Intel Macs work without editing the script.
Running `xcodebuild test` directly without generating fixtures first will fail the fixture-dependent suites (M3U, lyrics, WAV) — those are missing-file errors, not real regressions.

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
- Signing is ad-hoc by default. If you get `Command CodeSign failed`, set signing to "Sign to Run Locally" in target settings.
- If you get `Sandbox: deny file-read-data`, that is expected for files outside user selection — the app uses entitlements for user-selected file access only.

---

- Do NOT add `Co-authored-by:` trailers to git commits (see **Git commits** under Coding Conventions).

---

## Upstream Attribution

This project is forked from [`mbrukman/winamp-macos`](https://github.com/mbrukman/winamp-macos), originally by Matt Greenwood, MIT licensed. The upstream project was itself a tribute to the original Winamp by Nullsoft. The "Milkdrop"-style visualizations are an original native SwiftUI `Canvas` implementation in this fork, inspired by the classic Milkdrop look (no third-party preset engine is bundled).
