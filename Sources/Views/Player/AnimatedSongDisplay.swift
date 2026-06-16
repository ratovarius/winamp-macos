import AppKit
import SwiftUI

enum DisplayMode: String {
    case vestaboard
    case scrolling
    case scrollingUp
    case pixelated

    static let storageKey = "songDisplayMode"

    func cycled() -> DisplayMode {
        switch self {
        case .scrolling: .vestaboard
        case .vestaboard: .scrollingUp
        case .scrollingUp: .pixelated
        case .pixelated: .scrolling
        }
    }
}

struct AnimatedSongDisplay: View {
    let artist: String
    let title: String
    let trackId: UUID?
    @Binding var displayMode: DisplayMode

    /// Time anchor for the marquee. All animation is derived purely from the time
    /// elapsed since this instant (see `SongMarqueeAnimation`), so the `Canvas`
    /// never mutates observed `@State` mid-frame — which previously invalidated the
    /// whole window's SwiftUI view graph ~33×/sec and starved the main-thread Metal
    /// visualizer. Reset only on track or display-mode change (rare).
    @State private var animationEpoch = Date()

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch self.displayMode {
                case .scrolling:
                    self.scrollingDisplay(width: geometry.size.width)
                case .vestaboard:
                    self.vestaboardDisplay(width: geometry.size.width)
                case .scrollingUp:
                    self.scrollingUpDisplay(
                        width: geometry.size.width, height: geometry.size.height)
                case .pixelated:
                    self.pixelatedDisplay(width: geometry.size.width)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            self.displayMode = self.displayMode.cycled()
            self.resetAnimation()
        }
        .onChange(of: self.trackId) { _ in
            self.resetAnimation()
        }
        .onAppear {
            self.resetAnimation()
        }
    }

    private func scrollingDisplay(width: CGFloat) -> some View {
        let fullText = "\(artist) • \(title)"

        return TimelineView(.animation(minimumInterval: 0.03)) { context in
            let elapsed = context.date.timeIntervalSince(self.animationEpoch)
            Canvas { canvasContext, size in
                let text = Text(fullText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WinampColors.displayText)

                let resolved = canvasContext.resolve(text)
                let textWidth = resolved.measure(in: size).width

                // Check if text needs to scroll
                if textWidth > width - 12 {
                    // Scrolling text — derive offset from elapsed time (10 pt/s), looping.
                    let scrollDistance = textWidth + 200  // Add gap between loops
                    let offset = SongMarqueeAnimation.horizontalOffset(
                        elapsed: elapsed, speed: 10, scrollDistance: scrollDistance
                    )

                    // Draw text twice for seamless loop
                    canvasContext.draw(
                        resolved, at: CGPoint(x: 6 + offset, y: size.height / 2), anchor: .leading)
                    canvasContext.draw(
                        resolved, at: CGPoint(x: 6 + offset + scrollDistance, y: size.height / 2),
                        anchor: .leading)
                } else {
                    // Static text (fits) - center it
                    canvasContext.draw(
                        resolved, at: CGPoint(x: size.width / 2, y: size.height / 2),
                        anchor: .center)
                }
            }
        }
    }

    private func vestaboardDisplay(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.05)) { context in
            let elapsed = context.date.timeIntervalSince(self.animationEpoch)
            Canvas { canvasContext, size in
                // Derive the phase (reveal/hold of artist/title) purely from elapsed time.
                let frame = SongMarqueeAnimation.vestaboard(
                    elapsed: elapsed,
                    artistCount: self.artist.count,
                    titleCount: self.title.count,
                    charInterval: 0.1,
                    showDuration: 3.0
                )
                let fullText = frame.textIndex == 0 ? self.artist : self.title
                let availableWidth = width - 12

                if frame.isRevealing {
                    // Draw only revealed characters
                    let displayText = String(fullText.prefix(frame.revealedChars))
                    let revealedText = Text(displayText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WinampColors.displayText)
                    let revealedResolved = canvasContext.resolve(revealedText)
                    canvasContext.draw(
                        revealedResolved, at: CGPoint(x: 6, y: size.height / 2), anchor: .leading)
                } else {
                    let text = Text(fullText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WinampColors.displayText)
                    let resolved = canvasContext.resolve(text)
                    let textWidth = resolved.measure(in: size).width

                    // Text is fully revealed - check if it needs to scroll
                    if textWidth > availableWidth {
                        // Scrolling text — offset from time into the hold phase (6 pt/s).
                        let scrollDistance = textWidth + 100
                        let offset = SongMarqueeAnimation.horizontalOffset(
                            elapsed: frame.showElapsed, speed: 6, scrollDistance: scrollDistance
                        )

                        // Draw text twice for seamless loop
                        canvasContext.draw(
                            resolved, at: CGPoint(x: 6 + offset, y: size.height / 2),
                            anchor: .leading)
                        canvasContext.draw(
                            resolved,
                            at: CGPoint(x: 6 + offset + scrollDistance, y: size.height / 2),
                            anchor: .leading
                        )
                    } else {
                        // Static text (fits)
                        canvasContext.draw(
                            resolved, at: CGPoint(x: 6, y: size.height / 2), anchor: .leading)
                    }
                }
            }
        }
    }

    private func scrollingUpDisplay(width: CGFloat, height _: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.03)) { context in
            let elapsed = context.date.timeIntervalSince(self.animationEpoch)
            Canvas { canvasContext, size in
                // Line height is font-determined (single line); probe once so the
                // scroll geometry doesn't depend on which text is showing.
                let probe = canvasContext.resolve(
                    Text("Ag").font(.system(size: 11, weight: .medium)))
                let lineHeight = probe.measure(in: CGSize(width: width - 12, height: .infinity))
                    .height

                // Text starts below the visible area and scrolls up, pausing centered.
                let startY = size.height + lineHeight
                let totalDistance = startY + lineHeight
                let centerOffset = size.height / 2 + lineHeight + 2

                let frame = SongMarqueeAnimation.scrollUp(
                    elapsed: elapsed,
                    speed: 0.5 / 0.03,  // 16.7 pt/s — matches the prior 0.5 pt per 0.03 s tick
                    totalDistance: totalDistance,
                    centerOffset: centerOffset,
                    pause: 2.5
                )

                let currentText = frame.textIndex == 0 ? self.artist : self.title
                let resolved = canvasContext.resolve(
                    Text(currentText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WinampColors.displayText)
                )
                let currentY = startY - frame.offset
                canvasContext.draw(
                    resolved, at: CGPoint(x: size.width / 2, y: currentY), anchor: .center)
            }
        }
    }

    private func pixelatedDisplay(width _: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.03)) { context in
            let elapsed = context.date.timeIntervalSince(self.animationEpoch)
            Canvas { canvasContext, size in
                // Phase + fade progress derived from elapsed time (0.667 progress/s).
                let frame = SongMarqueeAnimation.pixelated(
                    elapsed: elapsed,
                    speed: 0.02 / 0.03,
                    cycleProgress: 2.5
                )
                let currentText = frame.textIndex == 0 ? self.artist : self.title

                // Draw each character with individual opacity based on progress and a
                // deterministic per-character offset (stable across frames).
                var xPos: CGFloat = 6.0
                for (index, char) in currentText.enumerated() {
                    let charProgress =
                        frame.progress + SongMarqueeAnimation.characterOffset(index: index)

                    // Calculate opacity: fade in from 0 to 1, then fade out from 1 to 0
                    let opacity: Double =
                        if charProgress < 1.0 {
                            // Fade in phase
                            max(0, min(1, charProgress))
                        } else {
                            // Fade out phase
                            max(0, min(1, 2.0 - charProgress))
                        }

                    // Add some vertical jitter during transition based on character index
                    let jitter = (1.0 - abs(1.0 - charProgress)) * 2.0  // Max jitter at mid-transition
                    let jitterAmount = abs(jitter)
                    let yOffset = sin(Double(index) * 0.5 + frame.progress * 3.0) * jitterAmount

                    let charText = Text(String(char))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WinampColors.displayText.opacity(opacity))

                    let resolved = canvasContext.resolve(charText)
                    let charWidth = resolved.measure(in: size).width

                    canvasContext.draw(
                        resolved, at: CGPoint(x: xPos, y: size.height / 2 + yOffset),
                        anchor: .leading)

                    xPos += charWidth
                }
            }
        }
    }

    private func resetAnimation() {
        self.animationEpoch = Date()
    }
}
