import AppKit

/// Winamp 2 / Webamp window snap graph (ported from webamp's `snapUtils.ts` + `resizeUtils.ts`).
enum WinampWindowSnap {
    static let snapDistance: CGFloat = 15

    struct Box {
        let minX: CGFloat
        let minY: CGFloat
        let width: CGFloat
        let height: CGFloat

        var maxX: CGFloat { minX + width }
        var maxY: CGFloat { minY + height }

        init(frame: CGRect) {
            self.minX = frame.minX
            self.minY = frame.minY
            self.width = frame.width
            self.height = frame.height
        }

        @MainActor
        init(window: NSWindow) {
            self.init(frame: window.frame)
        }
    }

    static func near(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) < self.snapDistance
    }

    static func overlapX(_ a: Box, _ b: Box) -> Bool {
        a.minX <= b.maxX + self.snapDistance && b.minX <= a.maxX + self.snapDistance
    }

    static func overlapY(_ a: Box, _ b: Box) -> Bool {
        a.minY <= b.maxY + self.snapDistance && b.minY <= a.maxY + self.snapDistance
    }

    /// True when two windows are edge-aligned within snap distance (Webamp `abuts`).
    static func abuts(_ a: Box, _ b: Box) -> Bool {
        guard self.overlapX(a, b) || self.overlapY(a, b) else { return false }

        if self.overlapX(a, b) {
            if self.near(a.maxY, b.minY) { return true }
            if self.near(a.minY, b.maxY) { return true }
        }
        if self.overlapY(a, b) {
            if self.near(a.minX, b.maxX) { return true }
            if self.near(a.maxX, b.minX) { return true }
        }
        return false
    }

    /// Flood-fill from `start` across windows that share a snap edge (Webamp `traceConnection`).
    @MainActor
    static func traceConnected(from start: NSWindow, among windows: [NSWindow]) -> [NSWindow] {
        let boxes = Dictionary(uniqueKeysWithValues: windows.map { ($0, Box(window: $0)) })
        var connected: Set<NSWindow> = [start]
        var queue = [start]

        while let node = queue.popLast() {
            guard let boxA = boxes[node] else { continue }
            for other in windows where !connected.contains(other) {
                guard let boxB = boxes[other] else { continue }
                if self.abuts(boxA, boxB) {
                    connected.insert(other)
                    queue.append(other)
                }
            }
        }

        return Array(connected)
    }

    /// Snap `box` against `other`, returning a new origin when an edge should stick.
    static func snappedOrigin(box: Box, origin: NSPoint, against other: Box) -> NSPoint? {
        var x = origin.x
        var y = origin.y
        var didSnap = false

        if self.overlapY(box, other) {
            if self.near(box.minX, other.maxX) {
                x = other.maxX
                didSnap = true
            } else if self.near(box.maxX, other.minX) {
                x = other.minX - box.width
                didSnap = true
            } else if self.near(box.minX, other.minX) {
                x = other.minX
                didSnap = true
            } else if self.near(box.maxX, other.maxX) {
                x = other.maxX - box.width
                didSnap = true
            }
        }

        if self.overlapX(box, other) {
            if self.near(box.maxY, other.minY) {
                y = other.minY - box.height
                didSnap = true
            } else if self.near(box.minY, other.maxY) {
                y = other.maxY
                didSnap = true
            } else if self.near(box.maxY, other.maxY) {
                y = other.maxY - box.height
                didSnap = true
            } else if self.near(box.minY, other.minY) {
                y = other.minY
                didSnap = true
            }
        }

        return didSnap ? NSPoint(x: x, y: y) : nil
    }

    @MainActor
    static func snappedOrigin(for window: NSWindow, against other: NSWindow) -> NSPoint? {
        self.snappedOrigin(
            box: Box(window: window),
            origin: window.frame.origin,
            against: Box(window: other)
        )
    }
}
