import AppKit
import SwiftUI

struct ShadeView: View {
    @EnvironmentObject var audioPlayer: AudioPlayer
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var isShadeMode: Bool
    @Binding var songDisplayMode: DisplayMode
    @Binding var showRemainingTime: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Title bar (draggable)
            ClassicTitleBar(isShadeMode: self.$isShadeMode)

            // Compact shade content with 3D effects
            HStack(spacing: 6) {
                // Mini spectrum with 3D inset
                ClassicVisualizerView()
                    .frame(width: 50, height: 20)
                    .background(Color.black)
                    .overlay(
                        // Inner shadow effect for depth
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.8), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .cornerRadius(3)
                    .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)

                // Playback control buttons
                HStack(spacing: 2) {
                    // Previous button
                    ShadeButton(icon: "⏮") {
                        self.playlistManager.previous()
                    }

                    // Play/Pause button
                    ShadeButton(icon: self.audioPlayer.isPlaying ? "⏸" : "▶") {
                        self.audioPlayer.togglePlayPause()
                    }

                    // Next button
                    ShadeButton(icon: "⏭") {
                        self.playlistManager.next()
                    }
                }

                // Time display with 3D inset
                Text(self.formatTime(
                    self.showRemainingTime ? -(self.audioPlayer.duration - self.audioPlayer.currentTime) : self.audioPlayer.currentTime,
                    showNegative: self.showRemainingTime
                ))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(WinampColors.displayText)
                .shadow(color: WinampColors.displayText.opacity(0.5), radius: 2, x: 0, y: 0)
                .frame(width: 50, height: 20)
                .background(
                    ZStack {
                        Color.black
                        // Inner shadow effect
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.8), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .cornerRadius(3)
                .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
                .onTapGesture {
                    self.showRemainingTime.toggle()
                }

                // Song title with animated visualization
                AnimatedSongDisplay(
                    artist: self.playlistManager.currentTrack?.artist ?? "DJ Mike Llama",
                    title: self.playlistManager.currentTrack?.title ?? "Llama Whippin' Intro",
                    trackId: self.playlistManager.currentTrack?.id,
                    displayMode: self.$songDisplayMode
                )
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background(
                    ZStack {
                        Color(red: 0.1, green: 0.12, blue: 0.18)
                        // Inner shadow effect
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.7), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .cornerRadius(3)
                .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                // Main background with subtle gradient
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

    func formatTime(_ time: TimeInterval, showNegative: Bool = false) -> String {
        let absTime = abs(time)
        let minutes = Int(absTime) / 60
        let seconds = Int(absTime) % 60
        let prefix = showNegative ? "-" : ""
        return String(format: "%@%d:%02d", prefix, minutes, seconds)
    }
}

/// Compact button for shade mode with 3D effect
struct ShadeButton: View {
    let icon: String
    let action: () -> Void
    @State private var isPressed = false
    @State private var isHovered = false

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
                        // Base button color with gradient
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: self.isPressed ?
                                        [Color(red: 0.15, green: 0.17, blue: 0.22), Color(red: 0.18, green: 0.20, blue: 0.26)] :
                                        self.isHovered ?
                                        [Color(red: 0.30, green: 0.34, blue: 0.42), Color(red: 0.24, green: 0.27, blue: 0.34)] :
                                        [Color(red: 0.26, green: 0.30, blue: 0.38), Color(red: 0.20, green: 0.23, blue: 0.30)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // 3D bevel effect
                        if !self.isPressed {
                            // Top-left highlight (raised)
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35), Color.clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )

                            // Bottom-right shadow
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
                            // Inverted bevel when pressed (inset)
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
                    // Outer border
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

// Removed duplicate WindowControlButton - using ModernWindowButton instead
