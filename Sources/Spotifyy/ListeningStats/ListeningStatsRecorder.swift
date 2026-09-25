import Foundation

/// Turns the shared player event stream into listening statistics.
///
/// The player only emits a state change on real events (play, pause, seek,
/// track change), not once a second while a track plays, so elapsed listening
/// time is credited from a one-second ticker that reads the last known
/// snapshot — the same approach the SponsorBlock skipper uses for its playhead.
final class SpotifyyListeningStatsRecorder {
    static let shared = SpotifyyListeningStatsRecorder()

    /// A track must play at least this long before it counts as a play, so
    /// skipping through an album does not inflate the play count.
    private static let minimumPlaySeconds: TimeInterval = 30
    /// Each tick credits at most this much wall-clock time: a suspended app or
    /// a clock jump must not book an hour of "listening".
    private static let maximumTickSeconds: TimeInterval = 5

    private let queue = DispatchQueue(label: "com.spotifyy.statsrecorder")
    private var ticker: DispatchSourceTimer?
    private var listener: UUID?
    private var started = false

    private var snapshot: SpotifyyPlayerSnapshot?
    private var lastTick: Date?
    private var currentURI = ""
    private var currentTitle = ""
    private var currentArtist = ""
    private var currentSeconds: TimeInterval = 0
    private var currentPlayCounted = false

    private init() {}

    func start() {
        let shouldStart = queue.sync { () -> Bool in
            guard !started else { return false }
            started = true
            return true
        }
        guard shouldStart else { return }

        listener = SpotifyyPlayerEventCenter.shared.addListener { [weak self] snapshot in
            guard let self = self else { return }
            self.queue.async { self.updateLocked(snapshot) }
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tickLocked() }
        timer.resume()
        queue.sync { ticker = timer }

        writeDebugLog("[Stats] recorder started")
    }

    func stop() {
        let token = queue.sync { () -> UUID? in
            ticker?.cancel()
            ticker = nil
            let token = listener
            listener = nil
            started = false
            return token
        }
        if let token = token {
            SpotifyyPlayerEventCenter.shared.removeListener(token)
        }
    }

    // MARK: - Events (caller holds `queue`)

    private func updateLocked(_ snapshot: SpotifyyPlayerSnapshot) {
        self.snapshot = snapshot

        if snapshot.uri.isEmpty || snapshot.uri == currentURI {
            // Same track — metadata can arrive a moment after the URI, so keep
            // the labels fresh instead of returning early.
            if !snapshot.title.isEmpty { currentTitle = snapshot.title }
            if !snapshot.artist.isEmpty { currentArtist = snapshot.artist }
            return
        }

        finalizeLocked()
        currentURI = snapshot.uri
        currentTitle = snapshot.title
        currentArtist = snapshot.artist
        currentSeconds = 0
        currentPlayCounted = false
    }

    private func tickLocked() {
        let now = Date()
        let elapsed = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now

        guard UserDefaults.listeningStatsEnabled else { return }
        guard let snapshot = snapshot, snapshot.isPlaying, !currentURI.isEmpty else { return }

        let credited = min(max(elapsed, 0), Self.maximumTickSeconds)
        guard credited > 0 else { return }

        currentSeconds += credited
        SpotifyyListeningStatsStore.shared.record(
            uri: currentURI, title: currentTitle, artist: currentArtist, seconds: credited
        )

        if !currentPlayCounted, currentSeconds >= Self.minimumPlaySeconds {
            currentPlayCounted = true
            SpotifyyListeningStatsStore.shared.recordPlay(
                uri: currentURI, title: currentTitle, artist: currentArtist
            )
        }
    }

    /// Credits the outgoing track's play (if it earned one) and clears the
    /// per-track state. Called before switching to a new track.
    private func finalizeLocked() {
        defer {
            currentURI = ""
            currentSeconds = 0
            currentPlayCounted = false
        }
        guard !currentURI.isEmpty else { return }
        guard !currentPlayCounted, currentSeconds >= Self.minimumPlaySeconds else { return }
        SpotifyyListeningStatsStore.shared.recordPlay(
            uri: currentURI, title: currentTitle, artist: currentArtist
        )
    }
}
