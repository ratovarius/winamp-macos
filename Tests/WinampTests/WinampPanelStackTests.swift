import XCTest
@testable import Winamp

/// Tests for the M2 ordered stack: the pure geometry→order resolver, the persisted model, and the
/// layout-state windowshade flag. These replace the former `WinampPanelDockingTests` (the
/// two-panel anchor special-case the stack model superseded).
final class WinampPanelStackTests: XCTestCase {
    // Classic frames: main at top, panels stacked flush below it (macOS coords, y up).
    private let mainFrame = CGRect(x: 100, y: 500, width: 275, height: 116)
    private func eqFrame(below anchor: CGRect) -> CGRect {
        CGRect(x: anchor.minX, y: anchor.minY - 84, width: 275, height: 84)
    }

    private func playlistFrame(below anchor: CGRect, height: CGFloat = 232) -> CGRect {
        CGRect(x: anchor.minX, y: anchor.minY - height, width: 275, height: height)
    }

    // MARK: - Resolver

    func testResolveStacksTwoPanelsBelowMainInOrder() {
        let eq = self.eqFrame(below: self.mainFrame)
        let playlist = self.playlistFrame(below: eq)
        let resolved = WinampPanelStackResolver.resolve(
            preferenceOrder: [.equalizer, .playlist],
            visibleFrames: [.equalizer: eq, .playlist: playlist],
            mainFrame: self.mainFrame
        )
        XCTAssertEqual(resolved.order, [.equalizer, .playlist])
        XCTAssertTrue(resolved.floating.isEmpty)
    }

    /// W5: a user can dock the EQ *below* the playlist and the resolver records that order rather
    /// than forcing the EQ back under the main window.
    func testResolveHonorsPlaylistAboveEqualizer() {
        let playlist = self.playlistFrame(below: self.mainFrame)
        let eq = self.eqFrame(below: playlist)
        let resolved = WinampPanelStackResolver.resolve(
            preferenceOrder: [.equalizer, .playlist],
            visibleFrames: [.equalizer: eq, .playlist: playlist],
            mainFrame: self.mainFrame
        )
        XCTAssertEqual(resolved.order, [.playlist, .equalizer])
        XCTAssertTrue(resolved.floating.isEmpty)
    }

    func testResolveMarksDetachedPanelFloating() {
        let faraway = CGRect(x: 900, y: 100, width: 275, height: 232)
        let resolved = WinampPanelStackResolver.resolve(
            preferenceOrder: [.equalizer, .playlist],
            visibleFrames: [.playlist: faraway],
            mainFrame: self.mainFrame
        )
        XCTAssertEqual(resolved.floating, [.playlist])
    }

    /// W2 (now structural): with the EQ hidden, only the playlist is visible and it docks directly
    /// below the main window — no gap where the EQ used to be.
    func testResolveDocksLonePlaylistBelowMain() {
        let playlist = self.playlistFrame(below: self.mainFrame)
        let resolved = WinampPanelStackResolver.resolve(
            preferenceOrder: [.equalizer, .playlist],
            visibleFrames: [.playlist: playlist],
            mainFrame: self.mainFrame
        )
        XCTAssertEqual(resolved.floating, [])
        XCTAssertEqual(resolved.order.first, .playlist)
    }

    // MARK: - Model

    @MainActor
    func testModelDefaultsToRegistryOrder() {
        let model = WinampPanelStackModel(defaultOrder: [.equalizer, .playlist], defaults: self.freshDefaults())
        XCTAssertEqual(model.order, [.equalizer, .playlist])
    }

    @MainActor
    func testDockedStackExcludesHiddenAndFloating() {
        let model = WinampPanelStackModel(defaultOrder: [.equalizer, .playlist], defaults: self.freshDefaults())
        model.floating = [.equalizer]
        XCTAssertEqual(model.dockedStack(visible: [.equalizer, .playlist]), [.playlist])
        XCTAssertEqual(model.dockedStack(visible: [.playlist]), [.playlist])
        XCTAssertEqual(model.dockedStack(visible: []), [])
    }

    @MainActor
    func testAnchorAboveReturnsPredecessorOrNil() {
        let model = WinampPanelStackModel(defaultOrder: [.equalizer, .playlist], defaults: self.freshDefaults())
        let visible: Set<WinampPanelID> = [.equalizer, .playlist]
        XCTAssertNil(model.anchorAbove(of: .equalizer, visible: visible))
        XCTAssertEqual(model.anchorAbove(of: .playlist, visible: visible), .equalizer)
    }

    @MainActor
    func testUpdatePersistsOrderAcrossInstances() {
        let defaults = self.freshDefaults()
        let first = WinampPanelStackModel(defaultOrder: [.equalizer, .playlist], defaults: defaults)
        first.update(order: [.playlist, .equalizer], floating: [])

        let second = WinampPanelStackModel(defaultOrder: [.equalizer, .playlist], defaults: defaults)
        XCTAssertEqual(second.order, [.playlist, .equalizer])
    }

    @MainActor
    func testNewlyRegisteredPanelIsAppendedToSavedOrder() {
        let defaults = self.freshDefaults()
        let first = WinampPanelStackModel(defaultOrder: [.playlist], defaults: defaults)
        first.update(order: [.playlist], floating: [])

        // A later launch registers an additional panel; it slots in after the saved order.
        let second = WinampPanelStackModel(defaultOrder: [.playlist, .equalizer], defaults: defaults)
        XCTAssertEqual(second.order, [.playlist, .equalizer])
    }

    // MARK: - Layout state (preserved from the former docking tests)

    @MainActor
    func testLayoutStateEqualizerDockedReflectsShadeMode() {
        let layout = WinampPanelLayoutState()
        layout.showEqualizer = true
        layout.isShadeMode = false
        XCTAssertTrue(layout.isEqualizerDocked)

        layout.isShadeMode = true
        XCTAssertFalse(layout.isEqualizerDocked)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "WinampPanelStackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
