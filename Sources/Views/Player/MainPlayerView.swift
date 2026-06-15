import AppKit
import SwiftUI

struct MainPlayerView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.winampUIScale) private var uiScale
    @Binding var showPlaylist: Bool
    @Binding var showEqualizer: Bool
    @Binding var isShadeMode: Bool
    @Binding var showVisualization: Bool
    @Binding var shuffleEnabled: Bool
    @Binding var repeatEnabled: Bool
    @Binding var songDisplayMode: DisplayMode
    @Binding var showRemainingTime: Bool

    @State private var seekDragging = false
    @State private var seekDragPercent: Double = 0
    @AppStorage("visualizationMode") private var visualizationMode: Int = 0
    @State private var showingSongInfo = false
    @State private var autoToggleMode = false
    @State private var autoToggleTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(isShadeMode: self.$isShadeMode)

            VStack(spacing: 0) {
                // Top section: Spectrum on left, song info on right
                HStack(spacing: 6) {
                    // LEFT: Spectrum visualizer with time above it
                    VStack(spacing: 0) {
                        // Time display with play/pause indicator - aligned right
                        HStack(spacing: 4) {
                            Spacer()

                            // Play/Pause button
                            Button(action: {
                                self.audioPlayer.togglePlayPause()
                            }) {
                                Image(systemName: self.audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(WinampColors.displayText)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)

                            SevenSegmentDisplay(
                                text: self.formatTime(
                                    self.showRemainingTime
                                        ? -(self.audioPlayer.duration - self.audioPlayer.currentTime)
                                        : self.audioPlayer.currentTime,
                                    showNegative: self.showRemainingTime
                                ),
                                digitWidth: 13 * uiScale,
                                digitHeight: 20 * uiScale,
                                spacing: 3 * uiScale
                            )
                            .onTapGesture {
                                self.showRemainingTime.toggle()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black)

                        // Spectrum visualizer with letters on the left
                        HStack(spacing: 0) {
                            // Letters vertically on the left
                            VStack(spacing: 0) {
                                Button(action: {
                                    self.visualizationMode = 1 // Oscilloscope
                                }) {
                                    Text("O")
                                        .winampFont(size: 10, weight: .bold, scale: uiScale)
                                        .foregroundColor(Color(white: 0.4))
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    self.visualizationMode = 0 // Analyzer bars
                                }) {
                                    Text("A")
                                        .winampFont(size: 10, weight: .bold, scale: uiScale)
                                        .foregroundColor(Color(white: 0.4))
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    self.showingSongInfo = true
                                    // Hide after 3 seconds
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                                        self.showingSongInfo = false
                                    }
                                }) {
                                    Text("I")
                                        .winampFont(size: 10, weight: .bold, scale: uiScale)
                                        .foregroundColor(Color(white: 0.4))
                                }
                                .buttonStyle(.plain)

                                Text("D")
                                    .winampFont(size: 10, weight: .bold, scale: uiScale)
                                    .foregroundColor(Color(white: 0.4))

                                Button(action: {
                                    self.autoToggleMode.toggle()
                                    if self.autoToggleMode {
                                        self.startAutoToggle()
                                    } else {
                                        self.stopAutoToggle()
                                    }
                                }) {
                                    Text("U")
                                        .winampFont(size: 10, weight: .bold, scale: uiScale)
                                        .foregroundColor(Color(white: 0.4))
                                }
                                .buttonStyle(.plain)

                                Text("V")
                                    .winampFont(size: 10, weight: .bold, scale: uiScale)
                                    .foregroundColor(Color(white: 0.4))
                            }
                            .frame(width: 14)
                            .padding(.leading, 4)
                            .offset(y: -15)

                            // Blue dotted vertical line separator
                            Canvas { context, size in
                                let dotSpacing: CGFloat = 3
                                let dotSize: CGFloat = 1
                                for y in stride(from: 0, to: size.height, by: dotSpacing) {
                                    let dotRect = CGRect(x: 0, y: y, width: dotSize, height: dotSize)
                                    context.fill(
                                        Path(ellipseIn: dotRect),
                                        with: .color(Color(red: 0.2, green: 0.4, blue: 0.8))
                                    )
                                }
                            }
                            .frame(width: 1)

                            // Visualizer
                            ClassicVisualizerView()
                                .background(Color.black)
                        }
                        .frame(height: 42)
                        .background(Color.black)
                    }
                    .frame(width: 185)
                    .background(Color.black)
                    .overlay(
                        // 3D inset effect - white highlight on top/left, dark shadow on bottom/right
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.15),
                                        Color.clear,
                                        Color.black.opacity(0.5),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .cornerRadius(4)

                    // RIGHT: Song info, bitrate, sliders, and buttons
                    VStack(spacing: 4) {
                        // Song title display with animated visualization or song info
                        if self.showingSongInfo {
                            // Show song information
                            VStack(spacing: 2) {
                                Text(self.audioFormatSummary)
                                    .winampFont(size: 10, weight: .bold, scale: uiScale)
                                    .foregroundColor(WinampColors.displayText)
                                Text("\(self.audioPlayer.currentChannels) channel\(self.audioPlayer.currentChannels > 1 ? "s" : "")")
                                    .winampFont(size: 9, scale: uiScale)
                                    .foregroundColor(Color.white.opacity(0.7))
                            }
                            .frame(height: 24)
                            .frame(maxWidth: .infinity)
                            .background(Color(red: 0.1, green: 0.12, blue: 0.18))
                            .cornerRadius(3)
                        } else {
                            // Normal song title display
                            AnimatedSongDisplay(
                                artist: self.playlistManager.currentTrack?.artist ?? "DJ Mike Llama",
                                title: self.playlistManager.currentTrack?.title ?? "Llama Whippin' Intro",
                                trackId: self.playlistManager.currentTrack?.id,
                                displayMode: self.$songDisplayMode
                            )
                            .frame(height: 24)
                            .background(Color(red: 0.1, green: 0.12, blue: 0.18))
                            .cornerRadius(3)
                        }

                        // Bitrate and format info row
                        HStack(spacing: 4) {
                            // Bitrate display with recessed effect
                            Text("\(self.audioPlayer.currentBitrate)")
                                .winampFont(size: 9, weight: .bold, scale: uiScale)
                                .foregroundColor(WinampColors.displayText)
                                .shadow(color: WinampColors.displayText.opacity(0.5), radius: 2, x: 0, y: 0)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.black.opacity(0.8),
                                                    Color.white.opacity(0.1),
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .cornerRadius(3)

                            Text("kbps")
                                .winampFont(size: 8, scale: uiScale)
                                .foregroundColor(Color.white.opacity(0.7))

                            // Sample rate display with recessed effect
                            Text(AudioFormatInfo.sampleRateDisplayKHz(self.audioPlayer.currentSampleRate))
                                .winampFont(size: 9, weight: .bold, scale: uiScale)
                                .foregroundColor(WinampColors.displayText)
                                .shadow(color: WinampColors.displayText.opacity(0.5), radius: 2, x: 0, y: 0)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    Color.black.opacity(0.8),
                                                    Color.white.opacity(0.1),
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                                .cornerRadius(3)

                            Text("kHz")
                                .winampFont(size: 8, scale: uiScale)
                                .foregroundColor(Color.white.opacity(0.7))

                            Spacer()

                            ForEach(
                                Array(AudioFormatInfo.channelIndicators(for: self.audioPlayer.currentChannels).enumerated()),
                                id: \.offset
                            ) { _, indicator in
                                Text(indicator.text)
                                    .winampFont(size: 8, weight: indicator.isActive ? .bold : .regular, scale: uiScale)
                                    .foregroundColor(indicator.isActive ? WinampColors.displayText : Color.white.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 4)

                        // Volume + balance sliders and EQ/PL buttons
                        HStack(spacing: 3 * uiScale) {
                            WinampVolumeSlider(
                                value: Binding(
                                    get: { Double(self.audioPlayer.volume) },
                                    set: { self.audioPlayer.setVolume(Float($0)) }
                                ),
                                scale: uiScale
                            )
                            .frame(width: 68 * uiScale, height: 13 * uiScale)

                            WinampBalanceSlider(
                                value: Binding(
                                    get: { Double(self.audioPlayer.balance) },
                                    set: { self.audioPlayer.setBalance(Float($0)) }
                                ),
                                scale: uiScale
                            )
                            .frame(width: 38 * uiScale, height: 13 * uiScale)

                            Spacer()

                            // EQ and PL buttons with indicator lights
                            HStack(spacing: 2) {
                                ModernToggleButtonWithLight(text: "EQ", isOn: self.$showEqualizer, scale: uiScale)
                                ModernToggleButtonWithLight(text: "PL", isOn: self.$showPlaylist, scale: uiScale)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)

                // Classic position bar: thin recessed trough + small notched thumb.
                GeometryReader { geo in
                    let thumbW: CGFloat = 29 * uiScale
                    let trackH: CGFloat = 10 * uiScale
                    let percent = CGFloat(self.seekDragging
                        ? self.seekDragPercent
                        : (self.audioPlayer.currentTime / max(self.audioPlayer.duration, 1)))
                    let thumbX = max(0, min(geo.size.width - thumbW, (geo.size.width - thumbW) * percent))

                    ZStack(alignment: .leading) {
                        // Recessed trough
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: trackH)
                            .overlay(
                                Rectangle().strokeBorder(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.9), WinampColors.borderLight.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                            )

                        // Notched silver thumb
                        ZStack {
                            RoundedRectangle(cornerRadius: 1 * uiScale)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.90, green: 0.92, blue: 0.96),
                                            Color(red: 0.62, green: 0.65, blue: 0.72),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 1 * uiScale)
                                        .strokeBorder(Color.black.opacity(0.55), lineWidth: 1)
                                )
                            // Vertical center notch
                            Rectangle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 2 * uiScale, height: trackH * 0.55)
                        }
                        .frame(width: thumbW, height: trackH)
                        .offset(x: thumbX)
                    }
                    .frame(height: trackH)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                self.seekDragging = true
                                self.seekDragPercent = max(0, min(1, Double(drag.location.x / geo.size.width)))
                            }
                            .onEnded { drag in
                                let percent = max(0, min(1, Double(drag.location.x / geo.size.width)))
                                let newTime = self.audioPlayer.duration * percent
                                self.audioPlayer.seek(to: max(0, min(newTime, self.audioPlayer.duration - 0.1)))
                                self.seekDragging = false
                            }
                    )
                }
                .frame(height: 12 * uiScale)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                // Control buttons row
                HStack(spacing: 4) {
                    HStack(spacing: 1) {
                        WinampTransportButton(glyph: .prev, width: 31, height: 24, scale: uiScale) { self.playlistManager.previous() }
                        WinampTransportButton(glyph: .play, width: 31, height: 24, scale: uiScale) { self.audioPlayer.playOrResume() }
                        WinampTransportButton(glyph: .pause, width: 31, height: 24, scale: uiScale) { self.audioPlayer.pause() }
                        WinampTransportButton(glyph: .stop, width: 31, height: 24, scale: uiScale) { self.audioPlayer.stop() }
                        WinampTransportButton(glyph: .next, width: 31, height: 24, scale: uiScale) { self.playlistManager.next() }
                    }

                    WinampTransportButton(glyph: .eject, width: 31, height: 24, scale: uiScale) { self.playlistManager.showFilePicker() }

                    Spacer()

                    HStack(spacing: 2) {
                        WinampToggle(text: "SHUFFLE", isOn: self.$shuffleEnabled, width: 60)
                        WinampToggle(text: "REPEAT", isOn: self.$repeatEnabled, width: 50)
                    }

                    // Visualization toggle button with icon
                    Button(action: { self.showVisualization.toggle() }) {
                        ZStack {
                            // Winamp icon
                            Image("WinampIcon")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .opacity(self.showVisualization ? 0.8 : 1.0)
                                .offset(x: self.showVisualization ? 1 : 0, y: self.showVisualization ? 1 : 0)
                                .shadow(
                                    color: self.showVisualization ? Color.black.opacity(0.6) : Color.black.opacity(0.3),
                                    radius: self.showVisualization ? 2 : 0,
                                    x: self.showVisualization ? -1 : 0,
                                    y: self.showVisualization ? -1 : 0
                                )
                                .shadow(
                                    color: self.showVisualization ? Color.clear : Color.white.opacity(0.15),
                                    radius: self.showVisualization ? 0 : 1,
                                    x: self.showVisualization ? 0 : -1,
                                    y: self.showVisualization ? 0 : -1
                                )
                                .shadow(
                                    color: self.showVisualization ? Color.clear : Color.black.opacity(0.4),
                                    radius: self.showVisualization ? 0 : 1,
                                    x: self.showVisualization ? 0 : 1,
                                    y: self.showVisualization ? 0 : 1
                                )
                        }
                        .frame(width: 32, height: 28)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(WinampColors.mainBg)
            .onTapGesture(count: 2) {
                self.isShadeMode = true
            }
            .frame(height: WinampMetrics.mainPlayerHeight * uiScale)
        }
        .frame(width: WinampUIScale.basePanelWidth * uiScale)
        .onDisappear {
            self.stopAutoToggle()
        }
    }

    private var audioFormatSummary: String {
        let bitrate = self.audioPlayer.currentBitrate
        let sampleRate = AudioFormatInfo.sampleRateDisplayKHz(self.audioPlayer.currentSampleRate)
        return "\(bitrate) kbps • \(sampleRate) kHz"
    }

    private func formatTime(_ time: TimeInterval, showNegative: Bool = false) -> String {
        let absTime = abs(time)
        let minutes = Int(absTime) / 60
        let seconds = Int(absTime) % 60
        let prefix = showNegative ? "-" : ""
        return String(format: "%@%d:%02d", prefix, minutes, seconds)
    }

    private func startAutoToggle() {
        // Toggle every 5 seconds
        self.autoToggleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.visualizationMode = self.visualizationMode == 0 ? 1 : 0
            }
        }
    }

    private func stopAutoToggle() {
        self.autoToggleTimer?.invalidate()
        self.autoToggleTimer = nil
    }
}
