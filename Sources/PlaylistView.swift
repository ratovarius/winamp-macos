import SwiftUI
import UniformTypeIdentifiers

struct PlaylistView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @Environment(\.winampUIScale) private var uiScale
    @State private var selectedTrack: Track.ID?
    @State private var tapTimer: Timer?
    @State private var lastTappedTrack: Track.ID?
    @State private var lastTrackCount = 0
    @State private var expandedArtists: Set<String> = []
    @AppStorage("playlistShowGrouped") private var showGrouped = false
    @State private var userInitiatedPlayback = false // Track if user clicked to play a song
    @State private var searchText = "" // Search filter text
    @State private var draggedTrackIndex: Int?

    // Resizing state
    @Binding var playlistSize: CGSize
    @Binding var isMinimized: Bool
    @State private var isDragging = false

    // Memoized derived views of the playlist. Recomputed only when the track list or
    // search text changes (see `recomputeDerivedTracks`), so unrelated re-renders
    // (selection, hover, drag, playback position) don't pay the O(n log n) grouping cost.
    @State private var filteredTracks: [(index: Int, track: Track)] = []
    @State private var groupedTracks: [(artist: String, tracks: [(index: Int, track: Track)])] = []

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

    /// Group filtered tracks by artist, preserving playlist order within each group.
    private static func groupTracks(
        _ filtered: [(index: Int, track: Track)]
    ) -> [(artist: String, tracks: [(index: Int, track: Track)])] {
        Dictionary(grouping: filtered, by: { $0.track.artist })
            .sorted { $0.key < $1.key }
            .map { (artist: $0.key, tracks: $0.value.sorted { $0.index < $1.index }) }
    }

    /// Refresh the memoized caches from the current track list and search text.
    private func recomputeDerivedTracks() {
        let filtered = Self.filterTracks(self.playlistManager.tracks, searchText: self.searchText)
        self.filteredTracks = filtered
        self.groupedTracks = Self.groupTracks(filtered)
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

            // Playlist content - flat or grouped (only when not minimized)
            if !self.isMinimized {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if self.showGrouped {
                                // Grouped view by artist
                                ForEach(self.groupedTracks, id: \.artist) { group in
                                    // Artist header (folder)
                                    ArtistHeader(
                                        artist: group.artist,
                                        trackCount: group.tracks.count,
                                        isExpanded: self.expandedArtists.contains(group.artist)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        self.toggleArtist(group.artist)
                                    }

                                    // Tracks under this artist (if expanded)
                                    if self.expandedArtists.contains(group.artist) {
                                        ForEach(group.tracks, id: \.track.id) { indexedTrack in
                                            self.playlistTrackRow(indexedTrack: indexedTrack, enableReorder: false)
                                        }
                                    }
                                }
                            } else {
                                // Flat view - all tracks (filtered)
                                ForEach(self.filteredTracks, id: \.track.id) { indexedTrack in
                                    self.playlistTrackRow(indexedTrack: indexedTrack, enableReorder: true)
                                }
                            }
                        }
                    }
                    .background(WinampColors.playlistBg)
                    .onChange(of: self.playlistManager.tracks.count) { newCount in
                        // When new tracks are added, expand all artists and scroll to show the last one
                        if newCount > self.lastTrackCount, !self.playlistManager.tracks.isEmpty {
                            // Auto-expand all artists when tracks are added
                            let allArtists = Set(playlistManager.tracks.map(\.artist))
                            self.expandedArtists = allArtists

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

                    // Toggle between flat and grouped view
                    PlaylistButton(text: self.showGrouped ? "FLAT" : "GRP") {
                        self.showGrouped.toggle()
                        if self.showGrouped {
                            // Auto-expand all artists when switching to grouped view
                            let allArtists = Set(playlistManager.tracks.map(\.artist))
                            self.expandedArtists = allArtists
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
        indexedTrack: (index: Int, track: Track),
        enableReorder: Bool
    ) -> some View {
        PlaylistTrackRow(
            indexedTrack: indexedTrack,
            isPlaying: indexedTrack.index == self.playlistManager.currentIndex,
            isSelected: indexedTrack.track.id == self.selectedTrack,
            enableReorder: enableReorder,
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
                self.playlistManager.removeTrack(at: index)
            },
            onMove: { from, to in
                self.playlistManager.moveTrack(from: from, to: to)
            }
        )
    }

    func toggleArtist(_ artist: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if self.expandedArtists.contains(artist) {
                self.expandedArtists.remove(artist)
            } else {
                self.expandedArtists.insert(artist)
            }
        }
    }

    func scrollToCurrentTrack(index: Int, proxy: ScrollViewProxy) {
        // Ensure the index is valid
        guard index >= 0, index < self.playlistManager.tracks.count else { return }

        let currentTrack = self.playlistManager.tracks[index]

        // If in grouped view, expand the artist of the current track
        if self.showGrouped {
            let artist = currentTrack.artist
            if !self.expandedArtists.contains(artist) {
                // Expand the artist first
                self.expandedArtists.insert(artist)
                // Small delay to allow the UI to update before scrolling
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    withAnimation {
                        proxy.scrollTo(currentTrack.id, anchor: .center)
                    }
                }
            } else {
                // Already expanded, just scroll
                withAnimation {
                    proxy.scrollTo(currentTrack.id, anchor: .center)
                }
            }
        } else {
            // Flat view - just scroll to the track
            withAnimation {
                proxy.scrollTo(currentTrack.id, anchor: .center)
            }
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
/// filtering/grouping on every `currentTime` tick — starving the main-thread Metal
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
    let isPlaying: Bool
    let isSelected: Bool
    let enableReorder: Bool
    let searchTextEmpty: Bool
    @Binding var selectedTrack: Track.ID?
    @Binding var lastTappedTrack: Track.ID?
    @Binding var tapTimer: Timer?
    @Binding var userInitiatedPlayback: Bool
    @Binding var draggedTrackIndex: Int?
    let onPlay: (Int) -> Void
    let onRemove: (Int) -> Void
    let onMove: (Int, Int) -> Void

    var body: some View {
        Button(action: self.handleTap) {
            ClassicPlaylistRow(
                track: self.indexedTrack.track,
                index: self.indexedTrack.index + 1,
                isPlaying: self.isPlaying,
                isSelected: self.isSelected
            )
        }
        .buttonStyle(.plain)
        .id(self.indexedTrack.track.id)
        .modifier(PlaylistTrackReorderModifier(
            enableReorder: self.enableReorder,
            trackIndex: self.indexedTrack.index,
            searchTextEmpty: self.searchTextEmpty,
            draggedTrackIndex: self.$draggedTrackIndex,
            onMove: self.onMove
        ))
        .contextMenu {
            Button("Play") {
                self.onPlay(self.indexedTrack.index)
            }
            Button("Remove") {
                self.onRemove(self.indexedTrack.index)
            }
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
    let enableReorder: Bool
    let trackIndex: Int
    let searchTextEmpty: Bool
    @Binding var draggedTrackIndex: Int?
    let onMove: (Int, Int) -> Void

    func body(content: Content) -> some View {
        if self.enableReorder {
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
        } else {
            content
        }
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
    let isPlaying: Bool
    let isSelected: Bool
    @Environment(\.winampUIScale) private var uiScale

    private var rowColor: Color {
        if self.isPlaying || self.isSelected { return .white }
        return WinampColors.playlistText
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * uiScale) {
            // Index with dot — simple "N." numbering, bold proportional (classic skin look)
            Text("\(self.index).")
                .winampFont(size: 14, weight: .bold, scale: uiScale)
                .foregroundColor(self.rowColor)
                .frame(minWidth: 22 * uiScale, alignment: .trailing)

            // Artist - Title
            Text("\(self.track.artist) - \(self.track.title)")
                .winampFont(size: 14, weight: .bold, scale: uiScale)
                .foregroundColor(self.rowColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6 * uiScale)

            // Duration
            Text(self.track.formattedDuration)
                .winampFont(size: 14, weight: .bold, scale: uiScale)
                .foregroundColor(self.rowColor)
        }
        .padding(.horizontal, 8 * uiScale)
        .padding(.vertical, 0)
        .frame(height: WinampMetrics.playlistRowHeight * uiScale)
        .background(
            self.isPlaying || self.isSelected ? WinampColors.playlistSelected : Color.clear
        )
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

/// Artist folder header
struct ArtistHeader: View {
    let artist: String
    let trackCount: Int
    let isExpanded: Bool
    @Environment(\.winampUIScale) private var uiScale

    var body: some View {
        HStack(spacing: 4) {
            Text(self.isExpanded ? "▼" : "▶")
                .winampFont(size: 8, weight: .bold, scale: uiScale)
                .foregroundColor(Color(red: 0.6, green: 0.8, blue: 0.6))
                .frame(width: 15)

            Text(self.artist)
                .winampFont(size: 8, weight: .bold, scale: uiScale)
                .foregroundColor(Color(red: 0.8, green: 0.9, blue: 0.8))
                .lineLimit(1)

            Spacer()

            Text("(\(self.trackCount))")
                .winampFont(size: 9, scale: uiScale)
                .foregroundColor(Color(red: 0.6, green: 0.8, blue: 0.6))
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(height: WinampMetrics.playlistRowHeight * uiScale + 2)
        .background(Color(red: 0.1, green: 0.15, blue: 0.1))
    }
}

/// Resize handle for bottom edge (vertical only)
struct ResizeHandle: View {
    @Environment(\.winampUIScale) private var uiScale
    @Binding var isDragging: Bool
    @Binding var playlistSize: CGSize
    @State private var startSize: CGSize = .zero
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Background area that's draggable - full width, small height
            Rectangle()
                .fill(Color.gray.opacity(0.001))
                .frame(height: 12)

            // Visual indicator (horizontal lines for vertical resize)
            HStack(spacing: 2) {
                ForEach(0 ..< 3) { i in
                    Rectangle()
                        .fill(i % 2 == 0 ? WinampColors.buttonDark : WinampColors.buttonLight)
                        .frame(width: 8, height: 1)
                }
            }
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
                    // Width tracks the scaled panel; height is user-resizable.
                    let newHeight = max(150, startSize.height + value.translation.height)
                    self.playlistSize = CGSize(width: WinampUIScale.basePanelWidth * uiScale, height: newHeight)
                }
                .onEnded { _ in
                    self.isDragging = false
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
                self.isHovering = true
            } else if self.isHovering {
                NSCursor.pop()
                self.isHovering = false
            }
        }
    }
}
