import Foundation

struct SleepTimerOptions: Codable {
    /// Pre-selected preset, so reopening the screen offers the duration the
    /// user picked last time instead of resetting to 30.
    var lastUsedMinutes: Int = 30
    /// "Pause when the current track ends" is a mode users tend to keep on.
    var endOfTrackByDefault: Bool = false
    var showToast: Bool = true

    /// Offered durations, in minutes.
    static let presets: [Int] = [5, 10, 15, 20, 30, 45, 60, 90]
}

extension UserDefaults {
    @UserDefault(key: "sleepTimerOptions", defaultValue: SleepTimerOptions())
    static var sleepTimerOptions
}
