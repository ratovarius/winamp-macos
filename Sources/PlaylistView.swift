import SwiftUI
import UniformTypeIdentifiers

struct PlaylistView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.winampUIScale) private var uiScale
    @State private var selectedTrack: Track.ID?
    @State private var tapTimer: Timer?
    @State private var lastTappedTrack: Track.ID?
    @State private var lastTrackCount = 0
    @State private var userInitiatedPlayback = false // Track if user clicked to play a song
    @State private var searchText = "" // Search filter text
    @State private var draggedTrackIndex: Int?
    @State private var keyboardNavigation = PlaylistKeyboardNavigation()

    // Resizing state
    @Binding var playlistSize: CGSize
    @Binding var isMinimized: Bool
    @State private var isDragging = false

    // Memoized filtered playlist. Recomputed only when the track list or search text
    // changes (see `recomputeDerivedTracks`), so unrelated re-renders (selection, hover,
    // drag, playback position) don't re-filter on every tick.
    @State private var filteredTracks: [(index: Int, track: Track)] = []

    /// Filter tracks by a title/artist substring match. Pure to keep the memoization
    /// logic independent of view state.
    private static func filterTracks(
        _ tracks: [Track],
        searchText: String
    ) -> [(index: Int, track: Track)] {
        if searchText.isEmpty {
            return Array(tracks.enumerated().map { ($0.offset, $0.element) })
        }

        let lowercasedSearch = searchText.lowercased()
        return tracks.enumerated().compactMap { index, track in
            let matchesTitle = track.title.lowercased().contains(lowercasedSearch)
            let matchesArtist = track.artist.lowercased().contains(lowercasedSearch)
            return (matchesTitle || matchesArtist) ? (index, track) : nil
        }
    }

    /// Refresh the memoized cache from the current track list and search text.
    private func recomputeDerivedTracks() {
        self.filteredTracks = Self.filterTracks(self.playlistManager.tracks, searchText: self.searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Classic Winamp Playlist header
            HStack(spacing: 3) {
                HStack(spacing: 3) {
                    Image(systemName: "waveform")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 9, height: 9)

                    Text("Winamp Playlist")
                        .winampFont(size: 9, scale: uiScale)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 4)
                .background(WinampColors.titleBar)

                Spacer()

                // Shade/minimize button
                Button(action: {
                    self.isMinimized.toggle()
                }) {
                    Image(systemName: self.isMinimized ? "chevron.down" : "chevron.up")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 9, height: 9)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 5 * uiScale)
            .frame(height: WinampMetrics.titleBarHeight * uiScale)
            .background(WinampTitleBarBackground())
            .overlay(alignment: .leading) {
                PanelTitleBarDragOverlay(excludedTrailingWidth: 20 * uiScale)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                self.isMinimized.toggle()
            }

            if !self.isMinimized {
                WinampSearchBar(text: self.$searchText, scale: uiScale)
                    .zIndex(100)
            }

            // Playlist content (only when not minimized)
            if !self.isMinimized {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(self.filteredTracks, id: \.track.id) { indexedTrack in
                                self.playlistTrackRow(indexedTrack: indexedTrack)
                            }
                        }
                    }
                    .background(WinampColors.playlistBg)
                    .onChange(of: self.playlistManager.tracks.count) { newCount in
                        if newCount > self.lastTrackCount, !self.playlistManager.tracks.isEmpty {
                            withAnimation {
                                proxy.scrollTo(self.playlistManager.tracks.last?.id, anchor: .bottom)
                            }
                        }
                        self.lastTrackCount = newCount
                    }
                    .onChange(of: self.playlistManager.currentIndex) { newIndex in
                        // Only auto-scroll if the change wasn't user-initiated
                        if !self.userInitiatedPlayback {
                            // This is an automatic track change (next/previous/auto-advance)
                            self.scrollToCurrentTrack(index: newIndex, proxy: proxy)
                        }
                        // Always reset the flag immediately after checking
                        self.userInitiatedPlayback = false
                    }
                }
                .zIndex(0) // Ensure ScrollView is below search box
                .onAppear {
                    self.keyboardNavigation.bind(
                        playlistManager: self.playlistManager,
                        isMinimized: { self.isMinimized },
                        visibleTracks: { self.filteredTracks },
                        selectedTrack: self.$selectedTrack,
                        userInitiatedPlayback: self.$userInitiatedPlayback
                    )
                    WinampPlaylistKeyboard.register(self.keyboardNavigation)
                }
                .onDisappear {
                    WinampPlaylistKeyboard.unregister(self.keyboardNavigation)
                    self.keyboardNavigation.unbind()
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    self.handleDrop(providers: providers)
                    return true
                }
            }

            // Bottom control bar
            HStack(spacing: 0) {
                // Left side - time display
                HStack(spacing: 4) {
                    PlaylistElapsedTimeLabel()

                    Text("/")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(WinampColors.displayInactive)

                    Text(WinampTimeFormatting.format(self.totalDuration))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(WinampColors.displayText)
                        .frame(width: 50, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(WinampColors.displayBg)

                Spacer()

                // Track count display
                Text("\(String(format: "%04d", self.playlistManager.tracks.count))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(WinampColors.displayText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WinampColors.displayBg)

                Spacer()

                // Right side - buttons
                HStack(spacing: 1) {
                    // ADD button with dropdown menu
                    PlaylistMenuButton(text: "ADD") {
                        Button("Add Files...") {
                            self.playlistManager.showFilePicker()
                        }
                        Button("Add Folder...") {
                            self.playlistManager.showFolderPicker()
                        }
                    }

                    PlaylistButton(text: "REM") {
                        if let selected = selectedTrack,
                           let index = playlistManager.tracks.firstIndex(where: { $0.id == selected })
                        {
                            self.playlistManager.removeTrack(at: index)
                            self.selectedTrack = nil
                        }
                    }

                    PlaylistButton(text: "SAVE") {
                        self.playlistManager.saveM3UPlaylist()
                    }

                    PlaylistButton(text: "CLR") {
                        self.playlistManager.clearPlaylist()
                    }
                }
            }
            .frame(height: 20)
            .background(WinampColors.mainBg)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                self.isMinimized.toggle()
            }

            // Resize handle at bottom edge (only when not minimized)
            if !self.isMinimized {
                ResizeHandle(isDragging: self.$isDragging, playlistSize: self.$playlistSize)
            }
        }
        .background(WinampColors.mainBgDark)
        .frame(width: self.playlistSize.width, height: self.isMinimized ? 50 : self.playlistSize.height)
        .onAppear { self.recomputeDerivedTracks() }
        .onChange(of: self.searchText) { _ in self.recomputeDerivedTracks() }
        .onChange(of: self.playlistManager.tracks) { _ in self.recomputeDerivedTracks() }
    }

    var totalDuration: TimeInterval {
        self.playlistManager.tracks.reduce(0) { $0 + $1.duration }
    }

    @ViewBuilder
    private func playlistTrackRow(
        indexedTrack: (index: Int, track: Track)
    ) -> some View {
        PlaylistTrackRow(
            indexedTrack: indexedTrack,
            isCurrentTrack: indexedTrack.index == self.playlistManager.currentIndex,
            isSelected: indexedTrack.track.id == self.selectedTrack,
            searchTextEmpty: self.searchText.isEmpty,
            selectedTrack: self.$selectedTrack,
            lastTappedTrack: self.$lastTappedTrack,
            tapTimer: self.$tapTimer,
            userInitiatedPlayback: self.$userInitiatedPlayback,
            draggedTrackIndex: self.$draggedTrackIndex,
            onPlay: { index in
                self.userInitiatedPlayback = true
                self.playlistManager.playTrack(at: index)
            },
            onRemove: { index in
                let removedID = self.playlistManager.tracks[index].id
                self.playlistManager.removeTrack(at: index)
                if self.selectedTrack == removedID {
                    self.selectedTrack = nil
                }
            },
            onGetInfo: { index in
                self.playlistManager.presentTrackInfo(at: index)
            },
            onRemoveFromDisk: { index in
                let removedID = self.playlistManager.tracks[index].id
                if self.playlistManager.removeTrackFromDisk(at: index),
                   self.selectedTrack == removedID
                {
                    self.selectedTrack = nil
                }
            },
            onMove: { from, to in
                self.playlistManager.moveTrack(from: from, to: to)
            }
        )
    }

    func scrollToCurrentTrack(index: Int, proxy: ScrollViewProxy) {
        guard index >= 0, index < self.playlistManager.tracks.count else { return }

        let currentTrack = self.playlistManager.tracks[index]
        withAnimation {
            proxy.scrollTo(currentTrack.id, anchor: .center)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                Task { @MainActor in
                    self.playlistManager.importDroppedURL(url)
                }
            }
        }
    }
}

/// Isolates the 10 Hz elapsed-time readout. Because the legacy `ObservableObject`
/// (`AudioPlayer`) re-renders every observing view on any `@Published` change, having
/// the whole `PlaylistView` observe it made the playlist re-run its O(n log n) track
/// filtering on every `currentTime` tick — starving the main-thread Metal
/// visualizer. Only this small label observes `currentTime` now.
private struct PlaylistElapsedTimeLabel: View {
    @EnvironmentObject var clock: PlaybackClock

    var body: some View {
        Text(WinampTimeFormatting.format(self.clock.currentTime))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(WinampColors.displayText)
            .frame(width: 50, alignment: .trailing)
    }
}

private struct PlaylistTrackRow: View {
    let indexedTrack: (index: Int, track: Track)
    let isCurrentTrack: Bool
    let isSelected: Bool
    let searchTextEmpty: Bool
    @Binding var selectedTrack: Track.ID?
    @Binding var lastTappedTrack: Track.ID?
    @Binding var tapTimer: Timer?
    @Binding var userInitiatedPlayback: Bool
    @Binding var draggedTrackIndex: Int?
    let onPlay: (Int) -> Void
    let onRemove: (Int) -> Void
    let onGetInfo: (Int) -> Void
    let onRemoveFromDisk: (Int) -> Void
    let onMove: (Int, Int) -> Void

    var body: some View {
        Button(action: self.handleTap) {
            ClassicPlaylistRow(
                track: self.indexedTrack.track,
                index: self.indexedTrack.index + 1,
                isCurrentTrack: self.isCurrentTrack,
                isSelected: self.isSelected
            )
        }
        .buttonStyle(.plain)
        .id(self.indexedTrack.track.id)
        .modifier(PlaylistTrackReorderModifier(
            trackIndex: self.indexedTrack.index,
            searchTextEmpty: self.searchTextEmpty,
            draggedTrackIndex: self.$draggedTrackIndex,
            onMove: self.onMove
        ))
        .contextMenu {
            Button("Play") {
                self.onPlay(self.indexedTrack.index)
            }
            Divider()
            Button("Get Info") {
                self.onGetInfo(self.indexedTrack.index)
            }
            .disabled(self.indexedTrack.track.url == nil)
            Button("Remove from Playlist") {
                self.onRemove(self.indexedTrack.index)
            }
            Button("Remove from Disk", role: .destructive) {
                self.onRemoveFromDisk(self.indexedTrack.index)
            }
            .disabled(self.indexedTrack.track.url == nil)
        }
    }

    private func handleTap() {
        let trackId = self.indexedTrack.track.id
        let trackIndex = self.indexedTrack.index

        self.selectedTrack = trackId

        if self.lastTappedTrack == trackId, let timer = self.tapTimer, timer.isValid {
            timer.invalidate()
            self.lastTappedTrack = nil
            self.userInitiatedPlayback = true
            self.onPlay(trackIndex)
        } else {
            self.lastTappedTrack = trackId
            self.tapTimer?.invalidate()
            let lastTapped = self.$lastTappedTrack
            self.tapTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                Task { @MainActor in
                    lastTapped.wrappedValue = nil
                }
            }
        }
    }
}

private struct PlaylistTrackReorderModifier: ViewModifier {
    let trackIndex: Int
    let searchTextEmpty: Bool
    @Binding var draggedTrackIndex: Int?
    let onMove: (Int, Int) -> Void

    func body(content: Content) -> some View {
        content
            .onDrag {
                guard self.searchTextEmpty else {
                    return NSItemProvider()
                }
                self.draggedTrackIndex = self.trackIndex
                return NSItemProvider(object: String(self.trackIndex) as NSString)
            }
            .onDrop(
                of: [.plainText],
                delegate: PlaylistRowDropDelegate(
                    destinationIndex: self.trackIndex,
                    draggedIndex: self.$draggedTrackIndex,
                    isEnabled: self.searchTextEmpty,
                    onMove: self.onMove
                )
            )
    }
}

struct PlaylistRowDropDelegate: DropDelegate {
    let destinationIndex: Int
    @Binding var draggedIndex: Int?
    let isEnabled: Bool
    let onMove: (Int, Int) -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        self.isEnabled && self.draggedIndex != nil
    }

    func dropEntered(info _: DropInfo) {
        guard self.isEnabled, let from = draggedIndex, from != destinationIndex else { return }
        self.onMove(from, self.destinationIndex)
        self.draggedIndex = self.destinationIndex
    }

    func performDrop(info _: DropInfo) -> Bool {
        self.draggedIndex = nil
        return true
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: self.isEnabled ? .move : .forbidden)
    }
}

struct ClassicPlaylistRow: View {
    let track: Track
    let index: Int
    let isCurrentTrack: Bool
    let isSelected: Bool
    @Environment(\.winampUIScale) private var uiScale

    private var indexColor: Color {
        self.isCurrentTrack ? WinampColors.playlistCurrentTrack : WinampColors.playlistText
    }

    private var titleColor: Color {
        self.isCurrentTrack ? WinampColors.playlistCurrentTrack : WinampColors.playlistText
    }

    private var durationColor: Color {
        self.isCurrentTrack ? WinampColors.playlistCurrentTrack : WinampColors.playlistText
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * uiScale) {
            // Index with dot — simple "N." numbering, bold proportional (classic skin look)
            Text("\(self.index).")
                .winampFont(size: 14, weight: .bold, scale: uiScale)
                .foregroundColor(self.indexColor)
                .frame(minWidth: 22 * uiScale, alignment: .trailing)

            // Artist - Title
            Text("\(self.track.artist) - \(self.track.title)")
                .winampFont(size: 14, weight: .bold, scale: uiScale)
                .foregroundColor(self.titleColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6 * uiScale)

            // Duration
            Text(self.track.formattedDuration)
                .winampFont(size: 14, weight: .bold, scale: uiScale)
                .foregroundColor(self.durationColor)
        }
        .padding(.horizontal, 8 * uiScale)
        .padding(.vertical, 0)
        .frame(height: WinampMetrics.playlistRowHeight * uiScale)
        .background(
            self.isSelected ? WinampColors.playlistSelected : Color.clear
        )
    }
}

/// Bridges playlist keyboard commands from `AppDelegate` into view-local selection state.
@MainActor
private final class PlaylistKeyboardNavigation: WinampPlaylistKeyboard.Handling {
    private weak var playlistManager: PlaylistManager?
    private var isMinimized: (() -> Bool)?
    private var visibleTracks: (() -> [(index: Int, track: Track)])?
    private var selectedTrack: Binding<Track.ID?>?
    private var userInitiatedPlayback: Binding<Bool>?

    func bind(
        playlistManager: PlaylistManager,
        isMinimized: @escaping () -> Bool,
        visibleTracks: @escaping () -> [(index: Int, track: Track)],
        selectedTrack: Binding<Track.ID?>,
        userInitiatedPlayback: Binding<Bool>
    ) {
        self.playlistManager = playlistManager
        self.isMinimized = isMinimized
        self.visibleTracks = visibleTracks
        self.selectedTrack = selectedTrack
        self.userInitiatedPlayback = userInitiatedPlayback
    }

    func unbind() {
        self.playlistManager = nil
        self.isMinimized = nil
        self.visibleTracks = nil
        self.selectedTrack = nil
        self.userInitiatedPlayback = nil
    }

    func moveSelection(by offset: Int) {
        guard self.isMinimized?() == false,
              let visibleTracks = self.visibleTracks?(),
              !visibleTracks.isEmpty,
              let selectedTrack = self.selectedTrack
        else { return }

        let anchorIndex = Self.anchorVisibleIndex(
            in: visibleTracks,
            selectedID: selectedTrack.wrappedValue,
            currentPlaylistIndex: self.playlistManager?.currentIndex ?? -1
        )
        let nextIndex = min(max(anchorIndex + offset, 0), visibleTracks.count - 1)
        selectedTrack.wrappedValue = visibleTracks[nextIndex].track.id
    }

    func playSelectedTrack() {
        guard let playlistManager = self.playlistManager,
              let visibleTracks = self.visibleTracks?(),
              let selectedID = self.selectedTrack?.wrappedValue,
              let indexedTrack = visibleTracks.first(where: { $0.track.id == selectedID })
        else { return }

        self.userInitiatedPlayback?.wrappedValue = true
        playlistManager.playTrack(at: indexedTrack.index)
    }

    private static func anchorVisibleIndex(
        in visibleTracks: [(index: Int, track: Track)],
        selectedID: Track.ID?,
        currentPlaylistIndex: Int
    ) -> Int {
        if let selectedID,
           let selectedIndex = visibleTracks.firstIndex(where: { $0.track.id == selectedID })
        {
            return selectedIndex
        }
        if currentPlaylistIndex >= 0,
           let currentIndex = visibleTracks.firstIndex(where: { $0.index == currentPlaylistIndex })
        {
            return currentIndex
        }
        return 0
    }
}

struct PlaylistButton: View {
    let text: String
    let action: () -> Void
    @Environment(\.winampUIScale) private var uiScale

    var body: some View {
        WinampSilverTextButton(
            title: self.text,
            scale: self.uiScale,
            minWidth: 30,
            height: 16,
            action: self.action
        )
    }
}

/// Playlist menu button (looks like PlaylistButton but with dropdown menu)
struct PlaylistMenuButton<Content: View>: View {
    let text: String
    @ViewBuilder let menuContent: Content

    var body: some View {
        Menu {
            self.menuContent
        } label: {
            Text(self.text)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.12, green: 0.13, blue: 0.18))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .frame(minWidth: 30)
                .background(SilverBevel(isPressed: false))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

/// Resize handle for the bottom edge. Vertical drag resizes height; horizontal drag resizes width
/// (the playlist may grow wider than the main window, classic-Winamp style). Width is clamped to at
/// least the scaled panel width so the docked playlist never becomes narrower than its anchor.
struct ResizeHandle: View {
    @Environment(\.winampUIScale) private var uiScale
    @Binding var isDragging: Bool
    @Binding var playlistSize: CGSize
    @State private var startSize: CGSize = .zero
    @State private var isHovering = false

    private var minWidth: CGFloat { WinampMetrics.panelWidth * uiScale }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Full-width strip so the bottom edge is grabbable anywhere for vertical resize.
            Rectangle()
                .fill(Color.gray.opacity(0.001))
                .frame(height: 12)

            // Diagonal corner grip hints both-axis resize (classic playlist bottom-right grip).
            ResizeGrip()
                .padding(.trailing, 3)
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !self.isDragging {
                        // Store the starting size on first change
                        self.startSize = self.playlistSize
                        self.isDragging = true
                    }
                    let newWidth = max(self.minWidth, self.startSize.width + value.translation.width)
                    let newHeight = max(150, self.startSize.height + value.translation.height)
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.playlistSize = CGSize(width: newWidth, height: newHeight)
                    }
                }
                .onEnded { _ in
                    self.isDragging = false
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.crosshair.push()
                self.isHovering = true
            } else if self.isHovering {
                NSCursor.pop()
                self.isHovering = false
            }
        }
    }
}

/// Three diagonal strokes drawn in the bottom-right corner — the classic Winamp resize affordance.
private struct ResizeGrip: View {
    var body: some View {
        Canvas { context, size in
            for i in 0 ..< 3 {
                let inset = CGFloat(i) * 3 + 1
                var path = Path()
                path.move(to: CGPoint(x: size.width - inset, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height - inset))
                context.stroke(path, with: .color(WinampColors.buttonLight), lineWidth: 1)
            }
        }
        .frame(width: 9, height: 9)
        .allowsHitTesting(false)
    }
}
