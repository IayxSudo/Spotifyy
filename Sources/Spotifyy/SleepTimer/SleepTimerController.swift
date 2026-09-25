import Foundation

extension Notification.Name {
    /// Posted when the timer is armed, cancelled, or fires. Countdown ticks are
    /// not posted: the settings screen reads `remainingSeconds` from its own
    /// one-second publisher, so nothing has to broadcast every tick.
    static let spotifyySleepTimerChanged = Notification.Name("SpotifyySleepTimerChanged")
}

/// Pauses playback after a countdown, or when the current track finishes.
///
/// Threading: every stored property is only touched with `queue` held, which is
/// what the `Locked` suffix marks. The ticker runs on `queue` itself, so
/// anything it calls must take the state directly rather than re-entering the
/// queue — a `queue.sync` from inside a serial queue deadlocks.
///
/// The timer lives for the session only. It is deliberately not persisted:
/// restoring a deadline from a previous launch would pause music at a random
/// moment the user has long forgotten about, which is worse than losing the
/// timer when Spotify is killed.
final class SleepTimerController {
    static let shared = SleepTimerController()

    enum Mode {
        case countdown
        case endOfTrack
    }

    private let queue = DispatchQueue(label: "com.spotifyy.sleeptimer")
    private var ticker: DispatchSourceTimer?
    private var armed = false
    private var mode: Mode = .countdown
    private var deadline: Date?
    private var endOfTrackURI: String?
    private var playerListener: UUID?

    private init() {}

    // MARK: - State (public, queue-safe)

    var isActive: Bool {
        queue.sync { armed }
    }

    var activeMode: Mode? {
        queue.sync { armed ? mode : nil }
    }

    /// Seconds left, or nil when no countdown is running.
    var remainingSeconds: TimeInterval? {
        let deadline = queue.sync { self.deadline }
        guard let deadline = deadline else { return nil }
        return max(0, deadline.timeIntervalSinceNow)
    }

    // MARK: - Control

    @discardableResult
    func start(minutes: Int) -> Bool {
        let clamped = min(max(minutes, 1), 24 * 60)
        var options = UserDefaults.sleepTimerOptions
        options.lastUsedMinutes = clamped
        UserDefaults.sleepTimerOptions = options

        arm(mode: .countdown, deadline: Date().addingTimeInterval(TimeInterval(clamped * 60)))
        return true
    }

    @discardableResult
    func startEndOfTrack() -> Bool {
        // Remember which track is playing right now, so a *change* of URI is
        // what triggers the pause.
        let currentURI = SpotifyyPlayerEventCenter.shared.latest?.uri
        arm(mode: .endOfTrack, deadline: nil)
        queue.sync { endOfTrackURI = currentURI }
        return true
    }

    func cancel() {
        let wasActive = queue.sync { () -> Bool in
            guard armed else { return false }
            resetLocked()
            stopTickerLocked()
            return true
        }
        guard wasActive else { return }
        writeDebugLog("[SleepTimer] cancelled")
        notifyChanged()
    }

    private func arm(mode: Mode, deadline: Date?) {
        queue.sync {
            resetLocked()
            stopTickerLocked()
            armed = true
            self.mode = mode
            self.deadline = deadline
            if mode == .countdown { startTickerLocked() }
        }

        startPlayerListenerIfNeeded()
        writeDebugLog("[SleepTimer] armed mode=\(mode)\(deadline.map { " in \(Int($0.timeIntervalSinceNow))s" } ?? "")")
        notifyChanged()
    }

    /// Caller holds `queue`.
    private func resetLocked() {
        armed = false
        mode = .countdown
        deadline = nil
        endOfTrackURI = nil
    }

    // MARK: - Countdown

    /// Caller holds `queue`. The handler runs on `queue` too, hence no locking
    /// in the body beyond reading the fields directly.
    private func startTickerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.armed, let deadline = self.deadline else { return }
            guard deadline.timeIntervalSinceNow <= 0 else { return }
            self.fireLocked(reason: "countdown")
        }
        timer.resume()
        ticker = timer
    }

    /// Caller holds `queue`.
    private func stopTickerLocked() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: - End of track

    private func startPlayerListenerIfNeeded() {
        let needsListener = queue.sync { playerListener == nil }
        guard needsListener else { return }

        let token = SpotifyyPlayerEventCenter.shared.addListener { [weak self] snapshot in
            guard let self = self else { return }
            self.queue.async { self.handleLocked(snapshot) }
        }
        queue.sync { playerListener = token }
    }

    /// Caller holds `queue`.
    private func handleLocked(_ snapshot: SpotifyyPlayerSnapshot) {
        guard armed, mode == .endOfTrack, !snapshot.uri.isEmpty else { return }

        if let armedURI = endOfTrackURI, armedURI != snapshot.uri {
            fireLocked(reason: "next track started")
            return
        }

        // Second trigger for builds that report the same URI across tracks
        // (repeat-one, or a URI that never changes).
        if snapshot.durationSeconds > 0,
           snapshot.positionSeconds >= snapshot.durationSeconds - 0.5 {
            fireLocked(reason: "track finished")
        }
    }

    // MARK: - Firing

    /// Caller holds `queue` — either the ticker handler or the listener's
    /// async block. Side effects (pause, toast, notification) are all
    /// queue-agnostic, so they run here rather than being bounced around.
    private func fireLocked(reason: String) {
        guard armed else { return }
        resetLocked()
        stopTickerLocked()

        let paused = SpotifyyPlayerEventCenter.shared.pausePlayback()
        writeDebugLog("[SleepTimer] fired (\(reason)) — pause \(paused ? "ok" : "failed")")

        DispatchQueue.main.async {
            guard UserDefaults.sleepTimerOptions.showToast else { return }
            PopUpHelper.showPopUp(
                message: (paused ? "sleep_timer_finished" : "sleep_timer_pause_failed").localized,
                buttonText: "OK".uiKitLocalized
            )
        }

        notifyChanged()
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .spotifyySleepTimerChanged, object: nil)
        }
    }
}
