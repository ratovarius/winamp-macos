import AppKit
import SwiftUI

struct ShadeView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var isShadeMode: Bool
    @Binding var songDisplayMode: DisplayMode
    @Binding var showRemainingTime: Bool

    private var displayTrack: Track? {
        self.playlistManager.currentTrack ?? self.audioPlayer.currentTrack
    }

    var body: some View {
        VStack(spacing: 0) {
            ClassicTitleBar(isShadeMode: self.$isShadeMode)

            HStack(spacing: 6) {
                ShadeInsetPanel {
                    ClassicVisualizerView()
                        .frame(width: 50, height: 20)
                }

                HStack(spacing: 2) {
                    ShadeButton(icon: "⏮") {
                        self.playlistManager.previous()
                    }

                    ShadeButton(icon: self.audioPlayer.isPlaying ? "⏸" : "▶") {
                        self.audioPlayer.togglePlayPause()
                    }

                    ShadeButton(icon: "⏭") {
                        self.playlistManager.next()
                    }
                }

                ShadeInsetPanel {
                    ShadeTimeReadout(showRemainingTime: self.$showRemainingTime)
                }
                .onTapGesture {
                    self.showRemainingTime.toggle()
                }

                ShadeSongInsetPanel {
                    AnimatedSongDisplay(
                        artist: self.displayTrack?.artist ?? "DJ Mike Llama",
                        title: self.displayTrack?.title ?? "Llama Whippin' Intro",
                        trackId: self.displayTrack?.id,
                        displayMode: self.$songDisplayMode
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.20, blue: 0.26),
                        Color(red: 0.15, green: 0.17, blue: 0.22),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onTapGesture(count: 2) {
                self.isShadeMode = false
            }
        }
    }
}

/// The shade-mode time display. Observes `PlaybackClock` so the ~10 Hz updates re-render
/// only this readout, not the whole compact player.
private struct ShadeTimeReadout: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var clock: PlaybackClock
    @Binding var showRemainingTime: Bool

    var body: some View {
        Text(WinampTimeFormatting.format(
            self.showRemainingTime ? -(self.audioPlayer.duration - self.clock.currentTime) : self.clock.currentTime,
            showNegative: self.showRemainingTime
        ))
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundColor(WinampColors.displayText)
        .shadow(color: WinampColors.displayText.opacity(0.5), radius: 2, x: 0, y: 0)
        .frame(width: 50, height: 20)
    }
}

/// Compact button for shade mode with 3D effect
struct ShadeButton: View {
    let icon: String
    let action: () -> Void
    @State private var isPressed = false
    @State private var isHovered = false

    private var gradientColors: [Color] {
        if self.isPressed {
            return [Color(red: 0.15, green: 0.17, blue: 0.22), Color(red: 0.18, green: 0.20, blue: 0.26)]
        }
        if self.isHovered {
            return [Color(red: 0.30, green: 0.34, blue: 0.42), Color(red: 0.24, green: 0.27, blue: 0.34)]
        }
        return [Color(red: 0.26, green: 0.30, blue: 0.38), Color(red: 0.20, green: 0.23, blue: 0.30)]
    }

    var body: some View {
        Button(action: {
            self.isPressed = true
            self.action()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.isPressed = false
            }
        }) {
            Text(self.icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.6), radius: 1, x: 0, y: 1)
                .frame(width: 22, height: 18)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: self.gradientColors,
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        if !self.isPressed {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )

                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.clear, Color.black.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.7), Color.white.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.black.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: self.isPressed ? Color.clear : Color.black.opacity(0.4), radius: 2, x: 0, y: self.isPressed ? 0 : 1)
                .offset(y: self.isPressed ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
}
