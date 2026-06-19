import CoreGraphics
import Foundation

/// Pure, time-based animation math for the scrolling song-title display.
///
/// The previous implementation advanced the marquee by mutating `@State` from
/// inside the `Canvas` render closure every frame (~33×/sec). That invalidated the
/// whole window's SwiftUI view graph each tick and starved the main-thread Metal
/// visualizer down to a few frames per second. Every value here is a pure function
/// of elapsed time, so the view can derive what to draw from `TimelineView`'s clock
/// without mutating any observed state — and the math is unit-testable in isolation.
enum SongMarqueeAnimation {
    // MARK: - Horizontal scroll (scrolling mode + vestaboard show phase)

    /// Looping horizontal offset (≤ 0) for marquee text: advances at `speed`
    /// points/second and wraps every `scrollDistance` points so the duplicated
    /// second copy produces a seamless loop.
    static func horizontalOffset(elapsed: Double, speed: Double, scrollDistance: Double) -> CGFloat
    {
        guard scrollDistance > 0, elapsed > 0 else { return 0 }
        let advanced = (elapsed * speed).truncatingRemainder(dividingBy: scrollDistance)
        return CGFloat(-advanced)
    }

    // MARK: - Scrolling-up (bottom→top with a pause at center)

    struct ScrollUpFrame: Equatable {
        /// 0 = first text (artist), 1 = second text (title); alternates each segment.
        let textIndex: Int
        /// Vertical scroll progress in points from the segment start.
        let offset: CGFloat
    }

    /// One bottom-to-top pass per text, pausing `pause` seconds when the text is
    /// centered, then alternating between the two texts.
    static func scrollUp(
        elapsed: Double,
        speed: Double,
        totalDistance: Double,
        centerOffset: Double,
        pause: Double
    ) -> ScrollUpFrame {
        guard speed > 0, totalDistance > 0 else { return ScrollUpFrame(textIndex: 0, offset: 0) }
        let clampedCenter = min(max(centerOffset, 0), totalDistance)
        let centerTime = clampedCenter / speed
        let segmentDuration = totalDistance / speed + max(pause, 0)
        let normalized = max(elapsed, 0)
        let segment = Int(floor(normalized / segmentDuration))
        let local = normalized - Double(segment) * segmentDuration

        let offset: Double
        if local < centerTime {
            offset = local * speed
        } else if local < centerTime + pause {
            offset = clampedCenter
        } else {
            offset = (local - pause) * speed
        }
        return ScrollUpFrame(textIndex: segment % 2, offset: CGFloat(min(offset, totalDistance)))
    }

    // MARK: - Vestaboard (reveal a char at a time, hold, then the other text)

    struct VestaboardFrame: Equatable {
        /// 0 = artist, 1 = title.
        let textIndex: Int
        /// True while characters are being revealed one at a time.
        let isRevealing: Bool
        /// Number of characters revealed so far (valid while `isRevealing`).
        let revealedChars: Int
        /// Seconds elapsed into the show/hold phase (drives scrolling when not revealing).
        let showElapsed: Double
    }

    /// Cycle: reveal artist → hold artist → reveal title → hold title, repeat.
    static func vestaboard(
        elapsed: Double,
        artistCount: Int,
        titleCount: Int,
        charInterval: Double,
        showDuration: Double
    ) -> VestaboardFrame {
        let artistReveal = Double(max(artistCount, 0)) * charInterval
        let titleReveal = Double(max(titleCount, 0)) * charInterval
        let phase0End = artistReveal
        let phase1End = phase0End + showDuration
        let phase2End = phase1End + titleReveal
        let cycle = phase2End + showDuration
        guard cycle > 0 else {
            return VestaboardFrame(
                textIndex: 0, isRevealing: false, revealedChars: 0, showElapsed: 0)
        }
        let local = max(elapsed, 0).truncatingRemainder(dividingBy: cycle)

        if local < phase0End {
            let chars = min(artistCount, Int(local / charInterval))
            return VestaboardFrame(
                textIndex: 0, isRevealing: true, revealedChars: chars, showElapsed: 0)
        } else if local < phase1End {
            return VestaboardFrame(
                textIndex: 0, isRevealing: false, revealedChars: artistCount,
                showElapsed: local - phase0End)
        } else if local < phase2End {
            let chars = min(titleCount, Int((local - phase1End) / charInterval))
            return VestaboardFrame(
                textIndex: 1, isRevealing: true, revealedChars: chars, showElapsed: 0)
        } else {
            return VestaboardFrame(
                textIndex: 1, isRevealing: false, revealedChars: titleCount,
                showElapsed: local - phase2End)
        }
    }

    // MARK: - Pixelated (per-character fade in/out, then the other text)

    struct PixelatedFrame: Equatable {
        /// 0 = artist, 1 = title.
        let textIndex: Int
        /// Progress through the current text's fade cycle (0 ..< cycleProgress).
        let progress: Double
    }

    static func pixelated(elapsed: Double, speed: Double, cycleProgress: Double) -> PixelatedFrame {
        guard speed > 0, cycleProgress > 0 else { return PixelatedFrame(textIndex: 0, progress: 0) }
        let total = max(elapsed, 0) * speed
        let segment = Int(floor(total / cycleProgress))
        let progress = total.truncatingRemainder(dividingBy: cycleProgress)
        return PixelatedFrame(textIndex: segment % 2, progress: progress)
    }

    /// Deterministic per-character timing offset in `[0, maxOffset]`, stable for a
    /// given index. Replaces `Double.random`, which previously forced a `@State`
    /// write (and re-render) the first frame of every new string.
    static func characterOffset(index: Int, maxOffset: Double = 0.5) -> Double {
        var hash = UInt64(bitPattern: Int64(index) &+ 1) &* 0x9E37_79B9_7F4A_7C15
        hash ^= hash >> 29
        let unit = Double(hash % 1000) / 1000.0
        return unit * maxOffset
    }
}
