import XCTest
@testable import Winamp

final class WinampPanelDockingTests: XCTestCase {
    func testPlaylistAnchorsToEqualizerWhenDockedAndVisible() {
        let anchor = WinampPanelDocking.playlistAnchor(
            isEqualizerDocked: true,
            isEqualizerVisible: true,
            isEqualizerFloating: false
        )
        XCTAssertEqual(anchor, .equalizer)
    }

    func testPlaylistAnchorsToMainWhenEqualizerFloating() {
        let anchor = WinampPanelDocking.playlistAnchor(
            isEqualizerDocked: true,
            isEqualizerVisible: true,
            isEqualizerFloating: true
        )
        XCTAssertEqual(anchor, .main)
    }

    /// W2 regression: hiding the EQ leaves its window allocated but ordered out, so the docked
    /// flag can still read true for a frame. The playlist must anchor to the main window rather
    /// than stack below the now-invisible EQ (which opened an EQ-height gap under the main window).
    func testPlaylistAnchorsToMainWhenEqualizerHiddenButStillDocked() {
        let anchor = WinampPanelDocking.playlistAnchor(
            isEqualizerDocked: true,
            isEqualizerVisible: false,
            isEqualizerFloating: false
        )
        XCTAssertEqual(anchor, .main)
    }

    func testPlaylistAnchorsToMainInShadeMode() {
        let anchor = WinampPanelDocking.playlistAnchor(
            isEqualizerDocked: false,
            isEqualizerVisible: false,
            isEqualizerFloating: false
        )
        XCTAssertEqual(anchor, .main)
    }

    @MainActor
    func testLayoutStateEqualizerDockedReflectsShadeMode() {
        let layout = WinampPanelLayoutState()
        layout.showEqualizer = true
        layout.isShadeMode = false
        XCTAssertTrue(layout.isEqualizerDocked)

        layout.isShadeMode = true
        XCTAssertFalse(layout.isEqualizerDocked)
    }
}
