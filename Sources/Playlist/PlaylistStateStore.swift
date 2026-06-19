import Foundation

struct PersistedPlaylistState: Codable, Equatable {
    var trackPaths: [String]
    var currentIndex: Int
    var shuffleEnabled: Bool
    var repeatEnabled: Bool

    static let empty = PersistedPlaylistState(
        trackPaths: [],
        currentIndex: -1,
        shuffleEnabled: false,
        repeatEnabled: false
    )
}

final class PlaylistStateStore {
    private let stateKey: String
    private let userDefaults: UserDefaults

    init(
        userDefaults: UserDefaults = .standard,
        stateKey: String = "WinampPlaylistState"
    ) {
        self.userDefaults = userDefaults
        self.stateKey = stateKey
    }

    func loadState() -> PersistedPlaylistState? {
        guard let data = userDefaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(PersistedPlaylistState.self, from: data)
        else {
            return nil
        }
        return state
    }

    func saveState(_ state: PersistedPlaylistState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        self.userDefaults.set(data, forKey: self.stateKey)
    }

    func clearState() {
        self.userDefaults.removeObject(forKey: self.stateKey)
    }
}
