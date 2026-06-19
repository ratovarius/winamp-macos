@testable import Winamp
import XCTest

final class SecurityScopedBookmarkStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        super.setUp()
        self.suiteName = "winamp-bookmark-tests-\(UUID().uuidString)"
        self.userDefaults = try XCTUnwrap(UserDefaults(suiteName: self.suiteName))
    }

    override func tearDown() {
        self.userDefaults.removePersistentDomain(forName: self.suiteName)
        super.tearDown()
    }

    func testSaveBookmarkIncrementsCount() throws {
        let store = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-\(UUID().uuidString).txt")
        try "test".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        store.saveBookmark(for: fileURL)

        XCTAssertEqual(store.bookmarkCount, 1)
        XCTAssertTrue(store.hasActiveScope(fileURL))
    }

    func testRestoreLoadsPersistedBookmarks() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-restore-\(UUID().uuidString).txt")
        try "restore".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        writer.saveBookmark(for: fileURL)
        XCTAssertEqual(writer.bookmarkCount, 1)

        let reader = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        reader.restore()

        XCTAssertEqual(reader.bookmarkCount, 1)
    }

    func testReleaseAllClearsActiveScopes() throws {
        let store = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-release-\(UUID().uuidString).txt")
        try "release".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        store.saveBookmark(for: fileURL)
        XCTAssertGreaterThan(store.activeScopeCount, 0)

        store.releaseAll()
        XCTAssertEqual(store.activeScopeCount, 0)
    }

    func testDuplicateSaveDoesNotGrowBookmarkCount() throws {
        let store = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-dedup-\(UUID().uuidString).txt")
        try "dedup".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        store.saveBookmark(for: fileURL)
        store.saveBookmark(for: fileURL)
        store.saveBookmark(for: fileURL)

        XCTAssertEqual(store.bookmarkCount, 1)
        XCTAssertTrue(store.hasActiveScope(fileURL))
    }

    func testRestoreDedupesDuplicateBookmarks() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-dedup-restore-\(UUID().uuidString).txt")
        try "dedup-restore".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        writer.saveBookmark(for: fileURL)
        writer.saveBookmark(for: fileURL)

        let reader = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        reader.restore()

        XCTAssertEqual(reader.bookmarkCount, 1)
    }

    func testEnsureAccessReturnsFalseForUnbookmarkedNetworkPath() {
        let store = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let url = URL(fileURLWithPath: "/Volumes/WinampTestNAS-\(UUID().uuidString)/song.mp3")
        XCTAssertFalse(store.ensureAccess(for: url))
    }

    func testEnsureAccessResolvesPersistedBookmarkForPlainPath() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-plain-path-\(UUID().uuidString).txt")
        try "plain-path".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        writer.saveBookmark(for: fileURL)

        let reader = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        reader.restore()

        let plainPathURL = URL(fileURLWithPath: fileURL.path)
        XCTAssertTrue(reader.ensureAccess(for: plainPathURL))
    }

    func testEnsureAccessUsesParentFolderBookmarkForNestedFile() throws {
        let store = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookmark-parent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("song.mp3")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00]))

        store.saveBookmark(for: directory)
        XCTAssertTrue(store.ensureAccess(for: fileURL))
    }
}
