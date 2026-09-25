import Foundation
import SpotifyyC

/// A single, feature-neutral snapshot of what the player is doing right now.
///
/// Spotify hands its observers a raw `SPTPlayerState` object and every feature
/// that needs it has to dig values out by KVC key. Parsing it once here keeps
/// that digging in one place — and means a feature only has to describe what
/// it wants, not how to get it out of Spotify.
struct SpotifyyPlayerSnapshot {
    let uri: String
    let title: String
    let artist: String
    let isPodcast: Bool
    let isPlaying: Bool
    let positionSeconds: Double
    let durationSeconds: Double
    let playbackSpeed: Double

    var isEmpty: Bool { uri.isEmpty && title.isEmpty }

    static let empty = SpotifyyPlayerSnapshot(
        uri: "",
        title: "",
        artist: "",
        isPodcast: false,
        isPlaying: false,
        positionSeconds: 0,
        durationSeconds: 0,
        playbackSpeed: 1
    )

    /// Never throws, never crashes: every key is gated behind `responds(to:)`
    /// first, because `value(forKey:)` raises an ObjC exception (unrecoverable
    /// from Swift) for a key the class does not implement.
    init(state: AnyObject?) {
        let track = SpotifyyPlayerValue.object(state, ["track"])
        let rawURI = SpotifyyPlayerValue.first(track, keys: ["URI", "uri", "spotifyURI"], selector: "URI")

        uri = SpotifyyPlayerValue.string(rawURI)
        title = SpotifyyPlayerValue.string(
            SpotifyyPlayerValue.first(track, keys: ["trackTitle", "title", "name"], selector: "trackTitle")
        )
        artist = SpotifyyPlayerValue.string(
            SpotifyyPlayerValue.first(track, keys: ["artistName", "artistTitle", "artist"], selector: "artistName")
        )
        isPodcast = SpotifyyPlayerValue.bool(track, ["isPodcast"]) ?? false

        let rawPosition = SpotifyyPlayerValue.first(state, keys: ["position"], selector: nil)
        let rawDuration = SpotifyyPlayerValue.first(state, keys: ["duration"], selector: nil)
        let duration = SpotifyyPlayerValue.double(rawDuration)
        // Some player observers report seconds, others milliseconds. The same
        // >10_000 gate the SponsorBlock skipper uses: no track in the app is
        // longer than that in seconds, but plenty are in milliseconds.
        positionSeconds = SpotifyyPlayerValue.normalizeSeconds(SpotifyyPlayerValue.double(rawPosition), durationHint: duration)
        durationSeconds = SpotifyyPlayerValue.normalizeSeconds(duration, durationHint: duration)

        isPlaying = SpotifyyPlayerValue.bool(state, ["isPlaying"]) ?? false
        let speed = SpotifyyPlayerValue.double(SpotifyyPlayerValue.first(state, keys: ["playbackSpeed"], selector: nil))
        playbackSpeed = speed > 0 ? speed : 1
    }

    private init(uri: String, title: String, artist: String, isPodcast: Bool,
                 isPlaying: Bool, positionSeconds: Double, durationSeconds: Double,
                 playbackSpeed: Double) {
        self.uri = uri
        self.title = title
        self.artist = artist
        self.isPodcast = isPodcast
        self.isPlaying = isPlaying
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.playbackSpeed = playbackSpeed
    }
}

/// KVC helpers shared by the snapshot and the event hub.
enum SpotifyyPlayerValue {
    /// Reads the first key that the object actually responds to.
    ///
    /// `selector`, when given, is preferred: `URI()`, `trackTitle()` and
    /// `artistName()` are real methods on SPTPlayerTrack, while the generic
    /// keys are only there to survive a Spotify build that renamed them.
    static func first(_ object: AnyObject?, keys: [String], selector: String?) -> Any? {
        guard let object = object else { return nil }
        if let selector = selector, object.responds(to: Selector(selector)) {
            if let value = read(object, selector) { return value }
        }
        for key in keys {
            guard object.responds(to: Selector(key)) else { continue }
            if let value = read(object, key) { return value }
        }
        return nil
    }

    static func object(_ object: AnyObject?, _ keys: [String]) -> AnyObject? {
        guard let object = object else { return nil }
        for key in keys {
            guard object.responds(to: Selector(key)) else { continue }
            if let value = read(object, key) { return value as AnyObject }
        }
        return nil
    }

    static func string(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let url = value as? URL { return url.absoluteString }
        if let value = value { return String(describing: value) }
        return ""
    }

    static func bool(_ object: AnyObject?, _ keys: [String]) -> Bool? {
        first(object, keys: keys, selector: nil) as? Bool
    }

    static func double(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        return 0
    }

    static func normalizeSeconds(_ raw: Double, durationHint: Double) -> Double {
        if raw > 10_000 { return raw / 1000.0 }
        if durationHint > 10_000 { return raw / 1000.0 }
        return raw
    }

    private static func read(_ object: AnyObject, _ key: String) -> Any? {
        // The selector form (URI()/trackTitle()/artistName()) returns an object,
        // plain property keys go through KVC the way the SponsorBlock skipper
        // already reads position/duration/isPlaying on shipped builds.
        return object.value(forKey: key)
    }
}

/// Fan-out hub for player events, and the single owner of the live player
/// handle used for transport control.
///
/// Features subscribe with `addListener` and get a `SpotifyyPlayerSnapshot` on
/// every player state change instead of each installing its own observer on
/// SPTPlayerServiceImplementation.
final class SpotifyyPlayerEventCenter {
    static let shared = SpotifyyPlayerEventCenter()

    private let queue = DispatchQueue(label: "com.spotifyy.playerevents")
    private var listeners: [UUID: (SpotifyyPlayerSnapshot) -> Void] = [:]
    private var knownPlayer: AnyObject?
    private var cachedPauseSelector: Selector?

    /// Latest snapshot seen, for features that attach late (settings screens).
    private var lastSnapshot: SpotifyyPlayerSnapshot?
    var latest: SpotifyyPlayerSnapshot? { queue.sync { lastSnapshot } }

    /// Pause selectors, most specific first. SPTPlayer's transport is
    /// `pause` on the versions this tweak ships against; the others are
    /// defensive for builds that renamed it.
    private static let pauseSelectors = ["pause", "pausePlayback"]

    @discardableResult
    func addListener(_ listener: @escaping (SpotifyyPlayerSnapshot) -> Void) -> UUID {
        let token = UUID()
        queue.sync { listeners[token] = listener }
        return token
    }

    func removeListener(_ token: UUID) {
        queue.sync { listeners.removeValue(forKey: token) }
    }

    /// Entry point for the SPTPlayerObserver hook. `player` is nil for the
    /// single-argument `didChangeState:` shape, in which case the handle the
    /// two-argument callbacks handed us earlier is reused.
    func handleState(player: AnyObject?, state: AnyObject) {
        if let player = player { knownPlayer = player }
        let snapshot = SpotifyyPlayerSnapshot(state: state)
        let handlers = queue.sync { () -> [(SpotifyyPlayerSnapshot) -> Void] in
            lastSnapshot = snapshot
            return Array(listeners.values)
        }
        for handler in handlers { handler(snapshot) }
    }

    /// Pauses playback through the live player object.
    ///
    /// Returns false when no pause selector was found — the caller decides how
    /// to surface that (the sleep timer reports it instead of silently
    /// pretending it stopped anything).
    @discardableResult
    func pausePlayback() -> Bool {
        let player = queue.sync { knownPlayer }
        guard let player = player else {
            writeDebugLog("[PlayerEvents] pause requested but no player handle yet")
            return false
        }

        if let cached = cachedPauseSelector, player.responds(to: cached) {
            if invokePause(on: player, selector: cached) { return true }
        }

        for name in SpotifyyPlayerEventCenter.pauseSelectors {
            let selector = NSSelectorFromString(name)
            guard player.responds(to: selector) else { continue }
            guard invokePause(on: player, selector: selector) else { continue }
            cachedPauseSelector = selector
            return true
        }

        writeDebugLog("[PlayerEvents] no pause selector on \(type(of: player))")
        return false
    }

    private func invokePause(on player: AnyObject, selector: Selector) -> Bool {
        // objc_msgSend through the C shim rather than perform(_:): `pause`
        // returns void, and perform(_:) would hand ARC a garbage return value
        // to release for a method that never produced one.
        SpotifyyInvokeVoid(player, selector)
        writeDebugLog("[PlayerEvents] paused via -[\(type(of: player)) \(NSStringFromSelector(selector))]")
        return true
    }
}
