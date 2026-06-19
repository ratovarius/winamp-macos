# Winamp macOS

A native macOS application that recreates the classic Winamp experience for playing local audio files (MP3, FLAC, WAV).

> **This is a personal fork** of [`mbrukman/winamp-macos`](https://github.com/mbrukman/winamp-macos) (originally by Matt Greenwood, MIT licensed), itself a tribute to the original Winamp by Nullsoft.
> I'm continuing active development here at [`ratovarius/winamp-macos`](https://github.com/ratovarius/winamp-macos) — evolving the upstream proof-of-concept toward a production-quality, modern macOS music player while preserving the Winamp UX.

## Full Screen

![Fullscreen Visualizer](fullscreen.png)

## Minimized (Playlist + Main Window independently)

![Minimized Playlist](minimized.png)

## Features

- MP3, FLAC, and WAV playback
- Winamp-inspired UI with the signature compact floating window
- Playlist management with M3U support and drag-to-reorder
- Full playback controls (play, pause, stop, next, previous)
- Shuffle and repeat modes
- Media key & macOS Now Playing integration (Control Center / lock screen)
- Spectrum analyzer visualization
- 10-band equalizer
- Milkdrop-style visualizer (click the icon in the main app) with fullscreen mode
- File browser with drag-and-drop support

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later

## Building

### Using Xcode
1. Open `Winamp.xcodeproj` in Xcode
2. Select the Winamp scheme
3. Build and run (⌘R)

alternatively:

```bash
./build.sh --run        # debug build + launch
./build.sh --release    # release build
```

## Testing

Tests live in `Tests/WinampTests`. Run them via the project script, which generates the required fixtures first:

```bash
./scripts/run-tests.sh
```

## UI Fidelity

Classic Winamp 2.x layout and behavior are informed by **[Webamp](https://github.com/captbaritone/webamp)** ([webamp.org](https://webamp.org/)) — sprite coordinates, window dimensions, shade mode, and playlist chrome.

## Documentation

- [BUILDING.md](BUILDING.md) — full build instructions
- [USAGE.md](USAGE.md) — end-user usage guide
- [CHANGES.md](CHANGES.md) — changelog
- [docs/](docs/) — deeper engineering notes 

## License & Attribution

MIT License.

Forked from [`mbrukman/winamp-macos`](https://github.com/mbrukman/winamp-macos), © 2024 Matt Greenwood, MIT licensed. The upstream project was itself a tribute to the original Winamp by Nullsoft. This fork continues development independently.
