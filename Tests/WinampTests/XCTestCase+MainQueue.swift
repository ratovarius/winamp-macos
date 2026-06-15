@testable import Winamp
import XCTest

/// Mutable container for values written from `@Sendable` async callbacks in tests.
final class SendableBox<T>: @unchecked Sendable {
    var value: T

    init(_ value: T) {
        self.value = value
    }
}

extension XCTestCase {
    /// Yields the main actor so nested `Task { @MainActor }` callbacks can finish.
    func waitForMainQueue(timeout: TimeInterval = 2.0, file _: StaticString = #filePath, line _: UInt = #line) {
        let expectation = expectation(description: "main actor drain")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }

    /// Waits for a delayed main-actor callback (e.g. auto-play after import).
    func waitForMainQueue(after delay: TimeInterval, timeout: TimeInterval = 2.0, file _: StaticString = #filePath, line _: UInt = #line) {
        let expectation = expectation(description: "main actor yield after delay")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout + delay)
    }

    @MainActor
    func waitForTrackCount(
        _ expected: Int,
        on manager: PlaylistManager,
        timeout: TimeInterval = 3.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if manager.tracks.count == expected { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for \(expected) tracks, got \(manager.tracks.count)", file: file, line: line)
    }
}
