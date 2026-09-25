import Foundation

// MARK: - Models

/// All-time totals for one track. Kept separate from the per-day buckets so a
/// track whose plays aged out of the retention window still has a title.
struct SpotifyyListeningStatsTrack: Codable {
    var title: String
    var artist: String
    var seconds: Double
    var plays: Int
    var lastPlayed: Date
}

/// A small seconds/plays pair, reused for both a whole day and one track
/// inside one day.
struct SpotifyyListeningStatsCounters: Codable {
    var seconds: Double = 0
    var plays: Int = 0
}

struct SpotifyyListeningStatsData: Codable {
    var startedAt: Date = Date()
    var totalSeconds: Double = 0
    var totalPlays: Int = 0
    /// "yyyy-MM-dd" -> whole-day totals.
    var days: [String: SpotifyyListeningStatsCounters] = [:]
    /// "yyyy-MM-dd" -> track URI -> that track's totals for that day. This is
    /// what makes "top tracks this week" answerable without keeping a second
    /// copy of every track's history.
    var dayTracks: [String: [String: SpotifyyListeningStatsCounters]] = [:]
    var tracks: [String: SpotifyyListeningStatsTrack] = [:]
}

/// Hashable so it can be used directly as a SwiftUI `Picker` selection value.
struct SpotifyyListeningStatsPeriod: Hashable {
    enum Kind: Hashable {
        case today
        case week
        case month
        case allTime
    }

    let kind: Kind

    static let today = SpotifyyListeningStatsPeriod(kind: .today)
    static let week = SpotifyyListeningStatsPeriod(kind: .week)
    static let month = SpotifyyListeningStatsPeriod(kind: .month)
    static let allTime = SpotifyyListeningStatsPeriod(kind: .allTime)

    var localizedKey: String {
        switch kind {
        case .today:   return "listening_stats_period_today"
        case .week:    return "listening_stats_period_week"
        case .month:   return "listening_stats_period_month"
        case .allTime: return "listening_stats_period_all"
        }
    }
}

struct SpotifyyListeningStatsRanked {
    let name: String
    let seconds: Double
    let plays: Int
}

struct SpotifyyListeningStatsSummary {
    let seconds: Double
    let plays: Int
    let trackCount: Int
    let artists: [SpotifyyListeningStatsRanked]
    let tracks: [SpotifyyListeningStatsRanked]

    static let empty = SpotifyyListeningStatsSummary(
        seconds: 0, plays: 0, trackCount: 0, artists: [], tracks: []
    )

    var isEmpty: Bool { seconds <= 0 && plays == 0 }
}

// MARK: - Store

/// Local-only listening statistics: seconds listened and play counts, bucketed
/// by day, per track and per artist.
///
/// Nothing leaves the device — there is no request here, only a JSON file in
/// the app's Application Support directory. Writes are throttled because the
/// recorder reports every second.
final class SpotifyyListeningStatsStore {
    static let shared = SpotifyyListeningStatsStore()

    private let queue = DispatchQueue(label: "com.spotifyy.listeningstats")
    private var data = SpotifyyListeningStatsData()
    private var loaded = false
    private var lastSave = Date.distantPast

    private static let directoryName = "Spotifyy"
    private static let fileName = "ListeningStats.json"
    private static let saveInterval: TimeInterval = 10
    /// Day buckets are what the period picker needs; a year of them is plenty.
    private static let maxDays = 400
    /// Per-day track buckets are bigger, so they are kept for a shorter window.
    private static let maxTrackDays = 120
    private static let maxTracks = 500
    private static let topLimit = 25

    private init() {}

    // MARK: - Recording

    func record(uri: String, title: String, artist: String, seconds: Double) {
        guard !uri.isEmpty, seconds > 0 else { return }
        queue.async {
            self.loadIfNeededLocked()
            self.mutateLocked(uri: uri, title: title, artist: artist, seconds: seconds, countedPlay: false)
        }
    }

    func recordPlay(uri: String, title: String, artist: String) {
        guard !uri.isEmpty else { return }
        queue.async {
            self.loadIfNeededLocked()
            self.mutateLocked(uri: uri, title: title, artist: artist, seconds: 0, countedPlay: true)
        }
    }

    /// Single mutation path so the day bucket, the day/track bucket and the
    /// all-time totals can never drift apart.
    private func mutateLocked(uri: String, title: String, artist: String,
                              seconds: Double, countedPlay: Bool) {
        let now = Date()
        let key = dayKeyLocked(now)
        let playIncrement = countedPlay ? 1 : 0

        var day = data.days[key] ?? SpotifyyListeningStatsCounters()
        day.seconds += seconds
        day.plays += playIncrement
        data.days[key] = day

        var dayTracks = data.dayTracks[key] ?? [:]
        var dayEntry = dayTracks[uri] ?? SpotifyyListeningStatsCounters()
        dayEntry.seconds += seconds
        dayEntry.plays += playIncrement
        dayTracks[uri] = dayEntry
        data.dayTracks[key] = dayTracks

        var track = data.tracks[uri] ?? SpotifyyListeningStatsTrack(
            title: title, artist: artist, seconds: 0, plays: 0, lastPlayed: now
        )
        track.seconds += seconds
        track.plays += playIncrement
        if !title.isEmpty { track.title = title }
        if !artist.isEmpty { track.artist = artist }
        track.lastPlayed = now
        data.tracks[uri] = track

        data.totalSeconds += seconds
        data.totalPlays += playIncrement

        pruneLocked()
        saveLocked(force: countedPlay)
    }

    func reset() {
        queue.sync {
            data = SpotifyyListeningStatsData()
            loaded = true
            if let url = fileURL() {
                try? FileManager.default.removeItem(at: url)
            }
            saveLocked(force: true)
        }
    }

    // MARK: - Reading

    func summary(for period: SpotifyyListeningStatsPeriod) -> SpotifyyListeningStatsSummary {
        queue.sync {
            loadIfNeededLocked()
            return summaryLocked(for: period)
        }
    }

    private func summaryLocked(for period: SpotifyyListeningStatsPeriod) -> SpotifyyListeningStatsSummary {
        var perTrack: [String: SpotifyyListeningStatsCounters] = [:]
        var seconds: Double = 0
        var plays = 0

        if period.kind == .allTime {
            seconds = data.totalSeconds
            plays = data.totalPlays
            for (uri, track) in data.tracks {
                perTrack[uri] = SpotifyyListeningStatsCounters(seconds: track.seconds, plays: track.plays)
            }
        } else {
            for key in dayKeysLocked(for: period) {
                if let day = data.days[key] {
                    seconds += day.seconds
                    plays += day.plays
                }
                for (uri, entry) in data.dayTracks[key] ?? [:] {
                    var aggregate = perTrack[uri] ?? SpotifyyListeningStatsCounters()
                    aggregate.seconds += entry.seconds
                    aggregate.plays += entry.plays
                    perTrack[uri] = aggregate
                }
            }
        }

        guard !perTrack.isEmpty else {
            return SpotifyyListeningStatsSummary(
                seconds: seconds, plays: plays, trackCount: 0, artists: [], tracks: []
            )
        }

        var perArtist: [String: SpotifyyListeningStatsCounters] = [:]
        var rankedTracks: [SpotifyyListeningStatsRanked] = []
        for (uri, counters) in perTrack {
            let track = data.tracks[uri]
            // An empty name is left as "" on purpose: the view decides how to
            // label an unknown artist, and the store stays free of UI strings.
            let artist = track?.artist ?? ""
            var aggregate = perArtist[artist] ?? SpotifyyListeningStatsCounters()
            aggregate.seconds += counters.seconds
            aggregate.plays += counters.plays
            perArtist[artist] = aggregate

            let title = track?.title ?? ""
            rankedTracks.append(SpotifyyListeningStatsRanked(
                name: title.isEmpty ? uri : title,
                seconds: counters.seconds,
                plays: counters.plays
            ))
        }

        let rankedArtists = perArtist
            .map { SpotifyyListeningStatsRanked(name: $0.key, seconds: $0.value.seconds, plays: $0.value.plays) }
            .sorted { ($0.seconds, $0.plays) > ($1.seconds, $1.plays) }

        return SpotifyyListeningStatsSummary(
            seconds: seconds,
            plays: plays,
            trackCount: perTrack.count,
            artists: Array(rankedArtists.prefix(Self.topLimit)),
            tracks: Array(rankedTracks.sorted { ($0.seconds, $0.plays) > ($1.seconds, $1.plays) }.prefix(Self.topLimit))
        )
    }

    var trackingStarted: Date {
        queue.sync {
            loadIfNeededLocked()
            return data.startedAt
        }
    }

    // MARK: - Persistence

    private func fileURL() -> URL? {
        let manager = FileManager.default
        guard let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base
            .appendingPathComponent(Self.directoryName, isDirectory: true)
            .appendingPathComponent(Self.fileName)
    }

    private func loadIfNeededLocked() {
        guard !loaded else { return }
        loaded = true
        guard let url = fileURL(), FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let payload = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            data = try decoder.decode(SpotifyyListeningStatsData.self, from: payload)
        } catch {
            writeDebugLog("[Stats] load failed, starting fresh: \(error)")
            data = SpotifyyListeningStatsData()
        }
    }

    private func saveLocked(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSave) >= Self.saveInterval else { return }
        lastSave = now

        guard let url = fileURL() else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(data).write(to: url, options: .atomic)
        } catch {
            writeDebugLog("[Stats] save failed: \(error)")
        }
    }

    // MARK: - Pruning

    private func pruneLocked() {
        pruneDaysLocked(in: &data.days, limit: Self.maxDays)
        pruneDaysLocked(in: &data.dayTracks, limit: Self.maxTrackDays)

        guard data.tracks.count > Self.maxTracks else { return }
        let keep = data.tracks
            .sorted { ($0.value.seconds, $0.value.plays) > ($1.value.seconds, $1.value.plays) }
            .prefix(Self.maxTracks)
        data.tracks = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    /// Day keys are "yyyy-MM-dd", so plain string ordering is chronological.
    private func pruneDaysLocked<T>(in buckets: inout [String: T], limit: Int) {
        guard buckets.count > limit else { return }
        let expired = buckets.keys.sorted().prefix(buckets.count - limit)
        for key in expired { buckets.removeValue(forKey: key) }
    }

    // MARK: - Day keys

    private func dayKeyLocked(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func dayKeysLocked(for period: SpotifyyListeningStatsPeriod) -> [String] {
        switch period.kind {
        case .today:   return [dayKeyLocked(Date())]
        case .week:    return recentDayKeysLocked(7)
        case .month:   return recentDayKeysLocked(30)
        case .allTime: return Array(data.days.keys)
        }
    }

    private func recentDayKeysLocked(_ count: Int) -> [String] {
        let calendar = Calendar.current
        let now = Date()
        var keys: [String] = []
        for offset in 0..<count {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            keys.append(dayKeyLocked(date))
        }
        return keys
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed locale/calendar: a device set to a non-Gregorian calendar would
        // otherwise produce keys that no longer sort chronologically.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
