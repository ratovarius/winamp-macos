import MediaPlayer

/// Bridges system media keys / Control Center (`MPRemoteCommandCenter`) to player actions.
///
/// The command-center wiring (``installCommandTargets(on:)``) is a thin, untestable shell; the
/// routing — which player action each command maps to — lives in the `perform…` methods and the
/// injected ``Handlers``, so it is unit-testable without touching the shared command-center
/// singleton or a running engine.
@MainActor
final class RemoteCommandController {
    /// Player actions each remote command triggers. Defaults are no-ops so a freshly constructed
    /// controller is safe to invoke before handlers are wired.
    struct Handlers {
        var play: () -> Void = {}
        var pause: () -> Void = {}
        var toggle: () -> Void = {}
        var next: () -> Void = {}
        var previous: () -> Void = {}
    }

    private var handlers = Handlers()

    func setHandlers(_ handlers: Handlers) {
        self.handlers = handlers
    }

    // MARK: - Routing (testable)

    func performPlay() {
        self.handlers.play()
    }

    func performPause() {
        self.handlers.pause()
    }

    func performToggle() {
        self.handlers.toggle()
    }

    func performNext() {
        self.handlers.next()
    }

    func performPrevious() {
        self.handlers.previous()
    }

    // MARK: - Command-center wiring (thin shell)

    /// Enables and targets the play/pause/toggle/next/previous commands. Targets hop to the main
    /// actor before routing, matching `MPRemoteCommandCenter`'s non-isolated callback contract.
    func installCommandTargets(on commandCenter: MPRemoteCommandCenter = .shared()) {
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.performPlay() }
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.performPause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.performToggle() }
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.performNext() }
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.performPrevious() }
            return .success
        }
    }
}
