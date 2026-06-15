import AppKit
import SwiftUI

enum DisplayMode {
    case vestaboard
    case scrolling
    case scrollingUp
    case pixelated

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

    @State private var scrollOffset: CGFloat = 0
    @State private var vestaboardPhase: Int =
        0 // 0 = revealing artist, 1 = showing/scrolling artist, 2 = revealing title, 3 = showing/scrolling title
    @State private var revealedChars: Int = 0
    @State private var showingTimer: Double = 0
    @State private var vestaboardScrollOffset: CGFloat = 0
    @State private var scrollUpOffset: CGFloat = 0
    @State private var scrollUpPhase: Int = 0 // 0 = artist, 1 = title
    @State private var scrollUpPaused: Bool = false
    @State private var scrollUpPauseTimer: Double = 0
    @State private var pixelatedPhase: Int = 0 // 0 = artist, 1 = title
    @State private var pixelatedProgress: Double = 0 // 0 to 2 (0-1 = fade in, 1-2 = fade out)
    @State private var charRandomOffsets: [Double] = []

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch self.displayMode {
                case .scrolling:
                    self.scrollingDisplay(width: geometry.size.width)
                case .vestaboard:
                    self.vestaboardDisplay(width: geometry.size.width)
                case .scrollingUp:
                    self.scrollingUpDisplay(width: geometry.size.width, height: geometry.size.height)
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

        return TimelineView(.animation(minimumInterval: 0.03)) { _ in
            Canvas { context, size in
                let text = Text(fullText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WinampColors.displayText)

                let resolved = context.resolve(text)
                let textWidth = resolved.measure(in: size).width

                // Check if text needs to scroll
                if textWidth > width - 12 {
                    // Scrolling text
                    let scrollDistance = textWidth + 200 // Add gap between loops

                    // Draw text twice for seamless loop
                    context.draw(resolved, at: CGPoint(x: 6 + self.scrollOffset, y: size.height / 2), anchor: .leading)
                    context.draw(resolved, at: CGPoint(x: 6 + self.scrollOffset + scrollDistance, y: size.height / 2), anchor: .leading)

                    // Update scroll offset
                    Task { @MainActor in
                        self.scrollOffset -= 0.3
                        if self.scrollOffset <= -scrollDistance {
                            self.scrollOffset = 0
                        }
                    }
                } else {
                    // Static text (fits) - center it
                    context.draw(resolved, at: CGPoint(x: size.width / 2, y: size.height / 2), anchor: .center)
                }
            }
        }
    }

    private func vestaboardDisplay(width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            Canvas { context, size in
                // Determine which text to show based on phase
                let fullText: String
                let isRevealing: Bool

                switch self.vestaboardPhase {
                case 0: // Revealing artist
                    fullText = self.artist
                    isRevealing = true
                case 1: // Showing/scrolling artist
                    fullText = self.artist
                    isRevealing = false
                case 2: // Revealing title
                    fullText = self.title
                    isRevealing = true
                case 3: // Showing/scrolling title
                    fullText = self.title
                    isRevealing = false
                default:
                    fullText = ""
                    isRevealing = false
                }

                let text = Text(fullText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WinampColors.displayText)

                let resolved = context.resolve(text)
                let textWidth = resolved.measure(in: size).width
                let availableWidth = width - 12

                if isRevealing {
                    // Draw only revealed characters
                    let displayText = String(fullText.prefix(self.revealedChars))
                    let revealedText = Text(displayText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WinampColors.displayText)
                    let revealedResolved = context.resolve(revealedText)
                    context.draw(revealedResolved, at: CGPoint(x: 6, y: size.height / 2), anchor: .leading)
                } else {
                    // Text is fully revealed - check if it needs to scroll
                    if textWidth > availableWidth {
                        // Scrolling text
                        let scrollDistance = textWidth + 100

                        // Draw text twice for seamless loop
                        context.draw(resolved, at: CGPoint(x: 6 + self.vestaboardScrollOffset, y: size.height / 2), anchor: .leading)
                        context.draw(
                            resolved,
                            at: CGPoint(x: 6 + self.vestaboardScrollOffset + scrollDistance, y: size.height / 2),
                            anchor: .leading
                        )
                    } else {
                        // Static text (fits)
                        context.draw(resolved, at: CGPoint(x: 6, y: size.height / 2), anchor: .leading)
                    }
                }

                // Update animation state
                Task { @MainActor in
                    self.updateVestaboardAnimation(fullText: fullText, textWidth: textWidth, availableWidth: availableWidth)
                }
            }
        }
    }

    private func scrollingUpDisplay(width: CGFloat, height _: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.03)) { _ in
            Canvas { context, size in
                // Determine which text to show based on phase
                let currentText = self.scrollUpPhase == 0 ? self.artist : self.title

                let text = Text(currentText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(WinampColors.displayText)

                let resolved = context.resolve(text)
                let textHeight = resolved.measure(in: CGSize(width: width - 12, height: .infinity)).height

                // Create a scrolling window effect
                // Text starts below the visible area and scrolls up
                let startY = size.height + textHeight
                let endY = -textHeight
                let totalDistance = startY - endY
                // Calculate the scroll offset when text is centered
                let centerOffset = startY - (size.height / 2) + 2

                // Calculate current Y position based on scroll offset
                let currentY = startY - self.scrollUpOffset

                // Draw the text at the current position
                context.draw(resolved, at: CGPoint(x: size.width / 2, y: currentY), anchor: .center)

                // Update animation state
                Task { @MainActor in
                    self.updateScrollUpAnimation(totalDistance: totalDistance, centerOffset: centerOffset, viewHeight: size.height)
                }
            }
        }
    }

    private func updateScrollUpAnimation(totalDistance: CGFloat, centerOffset: CGFloat, viewHeight _: CGFloat) {
        // Calculate if text is centered
        // When scrollUpOffset equals centerOffset, the text should be centered
        let distanceFromCenter = abs(scrollUpOffset - centerOffset)

        // If we're within a threshold of the center and not already paused, start pause
        // Use a wider threshold range to catch the centering more reliably
        if distanceFromCenter < 5, !self.scrollUpPaused, self.scrollUpOffset > 10, self.scrollUpOffset < totalDistance - 10 {
            self.scrollUpPaused = true
            self.scrollUpPauseTimer = 0
        }

        // If paused, increment timer
        if self.scrollUpPaused {
            self.scrollUpPauseTimer += 0.03

            // Resume after 2.5 seconds
            if self.scrollUpPauseTimer >= 2.5 {
                self.scrollUpPaused = false
                self.scrollUpPauseTimer = 0
            }
        }

        // Only scroll if not paused
        if !self.scrollUpPaused {
            self.scrollUpOffset += 0.5
        }

        // When text has fully scrolled off the top, switch to the other text
        if self.scrollUpOffset >= totalDistance {
            self.scrollUpOffset = 0
            self.scrollUpPhase = self.scrollUpPhase == 0 ? 1 : 0
            self.scrollUpPaused = false
            self.scrollUpPauseTimer = 0
        }
    }

    private func pixelatedDisplay(width _: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 0.03)) { _ in
            Canvas { context, size in
                // Determine which text to show based on phase
                let currentText = self.pixelatedPhase == 0 ? self.artist : self.title

                // Ensure random offsets are initialized synchronously
                let offsets: [Double]
                if self.charRandomOffsets.count == currentText.count {
                    offsets = self.charRandomOffsets
                } else {
                    // Create default offsets for this frame
                    offsets = (0 ..< currentText.count).map { _ in Double.random(in: 0 ... 0.5) }
                    // Update state for next frame
                    Task { @MainActor in
                        if self.charRandomOffsets.count != currentText.count {
                            self.charRandomOffsets = offsets
                        }
                    }
                }

                // Draw each character with individual opacity based on progress and random offset
                var xPos: CGFloat = 6.0
                for (index, char) in currentText.enumerated() {
                    let randomOffset = index < offsets.count ? offsets[index] : 0
                    let charProgress = self.pixelatedProgress + randomOffset

                    // Calculate opacity: fade in from 0 to 1, then fade out from 1 to 0
                    let opacity: Double = if charProgress < 1.0 {
                        // Fade in phase
                        max(0, min(1, charProgress))
                    } else {
                        // Fade out phase
                        max(0, min(1, 2.0 - charProgress))
                    }

                    // Add some vertical jitter during transition based on character index
                    // Use a deterministic calculation instead of random
                    let jitter = (1.0 - abs(1.0 - charProgress)) * 2.0 // Max jitter at mid-transition
                    let jitterAmount = abs(jitter)
                    let yOffset = sin(Double(index) * 0.5 + self.pixelatedProgress * 3.0) * jitterAmount

                    let charText = Text(String(char))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(WinampColors.displayText.opacity(opacity))

                    let resolved = context.resolve(charText)
                    let charWidth = resolved.measure(in: size).width

                    context.draw(resolved, at: CGPoint(x: xPos, y: size.height / 2 + yOffset), anchor: .leading)

                    xPos += charWidth
                }

                // Update animation state
                Task { @MainActor in
                    self.updatePixelatedAnimation()
                }
            }
        }
    }

    private func updatePixelatedAnimation() {
        self.pixelatedProgress += 0.02

        // When fully faded out, switch to the other text
        if self.pixelatedProgress >= 2.5 {
            self.pixelatedProgress = 0
            self.pixelatedPhase = self.pixelatedPhase == 0 ? 1 : 0
            // Reset random offsets for new text
            let currentText = self.pixelatedPhase == 0 ? self.artist : self.title
            self.charRandomOffsets = (0 ..< currentText.count).map { _ in Double.random(in: 0 ... 0.5) }
        }
    }

    private func updateVestaboardAnimation(fullText: String, textWidth: CGFloat, availableWidth: CGFloat) {
        switch self.vestaboardPhase {
        case 0: // Revealing artist
            // Slowly reveal one character at a time
            if self.revealedChars < fullText.count {
                self.showingTimer += 0.05
                if self.showingTimer >= 0.1 { // Reveal a new character every 0.1 seconds
                    self.revealedChars += 1
                    self.showingTimer = 0
                }
            } else {
                // Finished revealing, move to showing phase
                self.vestaboardPhase = 1
                self.showingTimer = 0
                self.vestaboardScrollOffset = 0
            }

        case 1: // Showing/scrolling artist
            if textWidth > availableWidth {
                // Scroll if needed
                let scrollDistance = textWidth + 100
                self.vestaboardScrollOffset -= 0.3
                if self.vestaboardScrollOffset <= -scrollDistance {
                    self.vestaboardScrollOffset = 0
                }
            }

            // Wait a bit then move to title
            self.showingTimer += 0.05
            if self.showingTimer >= 3.0 { // Show for 3 seconds
                self.vestaboardPhase = 2
                self.revealedChars = 0
                self.showingTimer = 0
                self.vestaboardScrollOffset = 0
            }

        case 2: // Revealing title
            // Slowly reveal one character at a time
            if self.revealedChars < fullText.count {
                self.showingTimer += 0.05
                if self.showingTimer >= 0.1 { // Reveal a new character every 0.1 seconds
                    self.revealedChars += 1
                    self.showingTimer = 0
                }
            } else {
                // Finished revealing, move to showing phase
                self.vestaboardPhase = 3
                self.showingTimer = 0
                self.vestaboardScrollOffset = 0
            }

        case 3: // Showing/scrolling title
            if textWidth > availableWidth {
                // Scroll if needed
                let scrollDistance = textWidth + 100
                self.vestaboardScrollOffset -= 0.3
                if self.vestaboardScrollOffset <= -scrollDistance {
                    self.vestaboardScrollOffset = 0
                }
            }

            // Wait a bit then go back to artist
            self.showingTimer += 0.05
            if self.showingTimer >= 3.0 { // Show for 3 seconds
                self.vestaboardPhase = 0
                self.revealedChars = 0
                self.showingTimer = 0
                self.vestaboardScrollOffset = 0
            }

        default:
            break
        }
    }

    private func resetAnimation() {
        self.scrollOffset = 0
        self.vestaboardPhase = 0
        self.revealedChars = 0
        self.showingTimer = 0
        self.vestaboardScrollOffset = 0
        self.scrollUpOffset = 0
        self.scrollUpPhase = 0
        self.scrollUpPaused = false
        self.scrollUpPauseTimer = 0
        self.pixelatedPhase = 0
        self.pixelatedProgress = 0
        self.charRandomOffsets = []
    }
}
