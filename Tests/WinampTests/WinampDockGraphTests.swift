import XCTest
@testable import Winamp

/// Tests for the geometry-primary docking core: the pure 2D parent derivation (`WinampDockGraph`)
/// and the offset persistence (`WinampPanelPositionStore`). These replace the former
/// `WinampPanelStackTests` (the 1-D ordered model the geometry-primary design superseded).
final class WinampDockGraphTests: XCTestCase {
    private let main = CGRect(x: 100, y: 500, width: 275, height: 116)

    private func below(_ anchor: CGRect, height: CGFloat = 84) -> CGRect {
        CGRect(x: anchor.minX, y: anchor.minY - height, width: anchor.width, height: height)
    }

    private func rightOf(_ anchor: CGRect, width: CGFloat = 275, height: CGFloat = 232) -> CGRect {
        CGRect(x: anchor.maxX, y: anchor.maxY - height, width: width, height: height)
    }

    // MARK: - Vertical

    func testVerticalChainBelowMain() {
        let eq = self.below(self.main)
        let playlist = self.below(eq, height: 232)
        let parents = WinampDockGraph.parents(
            frames: [.main: self.main, .panel(.equalizer): eq, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.equalizer], .main)
        XCTAssertEqual(parents[.playlist], .panel(.equalizer))
        XCTAssertTrue(WinampDockGraph.floating(order: [.equalizer, .playlist], parents: parents).isEmpty)
    }

    func testReorderedVerticalChain() {
        // Playlist directly below main, EQ below the playlist.
        let playlist = self.below(self.main, height: 232)
        let eq = self.below(playlist)
        let parents = WinampDockGraph.parents(
            frames: [.main: self.main, .panel(.equalizer): eq, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.playlist], .main)
        XCTAssertEqual(parents[.equalizer], .panel(.playlist))
    }

    // MARK: - Horizontal (W: left/right docking)

    func testHorizontalDockToRightOfMain() {
        let playlist = self.rightOf(self.main)
        let parents = WinampDockGraph.parents(
            frames: [.main: self.main, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.playlist], .main, "a panel snapped to the main window's right edge docks to it")
    }

    func testHorizontalRowChainsLeftToRight() {
        // A horizontal row: main — EQ — playlist, each touching the previous window's right edge.
        // The playlist is far enough right that it only abuts the EQ, not the main window.
        let eq = CGRect(x: self.main.maxX, y: self.main.minY, width: 275, height: self.main.height)
        let playlist = CGRect(x: eq.maxX, y: self.main.minY, width: 275, height: self.main.height)
        let parents = WinampDockGraph.parents(
            frames: [.main: self.main, .panel(.equalizer): eq, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.equalizer], .main)
        XCTAssertEqual(parents[.playlist], .panel(.equalizer))
    }

    // MARK: - Floating

    func testDetachedPanelIsFloating() {
        let faraway = CGRect(x: 1200, y: 50, width: 275, height: 232)
        let parents = WinampDockGraph.parents(
            frames: [.main: self.main, .panel(.playlist): faraway],
            order: [.equalizer, .playlist]
        )
        XCTAssertNil(parents[.playlist])
        XCTAssertEqual(WinampDockGraph.floating(order: [.playlist], parents: parents), [.playlist])
    }

    func testLonePlaylistDocksDirectlyBelowMain() {
        // EQ hidden: only the playlist is present, snapped below main → docks to main (no gap).
        let playlist = self.below(self.main, height: 232)
        let parents = WinampDockGraph.parents(
            frames: [.main: self.main, .panel(.playlist): playlist],
            order: [.equalizer, .playlist]
        )
        XCTAssertEqual(parents[.playlist], .main)
    }
}

final class WinampPanelPositionStoreTests: XCTestCase {
    @MainActor
    func testStoreAndRestoreOffset() {
        let store = WinampPanelPositionStore(defaults: self.freshDefaults())
        let main = CGPoint(x: 100, y: 500)
        store.store(.playlist, panelOrigin: CGPoint(x: 120, y: 300), mainOrigin: main)

        XCTAssertEqual(store.offset(for: .playlist), CGSize(width: 20, height: -200))
        // Origin restores relative to a new main position.
        let restored = store.origin(for: .playlist, mainOrigin: CGPoint(x: 200, y: 600))
        XCTAssertEqual(restored, CGPoint(x: 220, y: 400))
    }

    @MainActor
    func testUnknownPanelHasNoOffset() {
        let store = WinampPanelPositionStore(defaults: self.freshDefaults())
        XCTAssertNil(store.offset(for: .equalizer))
        XCTAssertNil(store.origin(for: .equalizer, mainOrigin: .zero))
    }

    @MainActor
    func testOffsetPersistsAcrossInstances() {
        let defaults = self.freshDefaults()
        let first = WinampPanelPositionStore(defaults: defaults)
        first.store(.equalizer, panelOrigin: CGPoint(x: 100, y: 416), mainOrigin: CGPoint(x: 100, y: 500))

        let second = WinampPanelPositionStore(defaults: defaults)
        XCTAssertEqual(second.offset(for: .equalizer), CGSize(width: 0, height: -84))
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "WinampPanelPositionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
