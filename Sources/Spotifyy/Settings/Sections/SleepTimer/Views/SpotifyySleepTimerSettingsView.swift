import Combine
import SwiftUI
import UIKit

struct SpotifyySleepTimerSettingsView: View {
    /// Drives the countdown label. The controller deliberately does not post a
    /// notification every second — the screen asks it for the remaining time
    /// on its own tick.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @State private var armed = SleepTimerController.shared.isActive
    @State private var mode = SleepTimerController.shared.activeMode
    @State private var remaining: TimeInterval? = SleepTimerController.shared.remainingSeconds
    @State private var options = UserDefaults.sleepTimerOptions

    var body: some View {
        List {
            Section(
                header: Text("sleep_timer_section".localized),
                footer: Text("sleep_timer_footer".localized)
            ) {
                statusRow

                if armed {
                    Button {
                        SleepTimerController.shared.cancel()
                        refresh()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "xmark.circle.fill")
                            Text("sleep_timer_cancel".localized)
                        }
                        .foregroundColor(.red)
                    }
                }
            }

            Section(header: Text("sleep_timer_duration_section".localized)) {
                ForEach(SleepTimerOptions.presets, id: \.self) { minutes in
                    Button {
                        SleepTimerController.shared.start(minutes: minutes)
                        refresh()
                    } label: {
                        presetRow(minutes)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Section(footer: Text("sleep_timer_end_of_track_footer".localized)) {
                Button {
                    SleepTimerController.shared.startEndOfTrack()
                    refresh()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.right.to.line")
                            .frame(width: 22)
                        Text("sleep_timer_end_of_track".localized)
                        Spacer()
                        if isWaitingForTrackEnd {
                            Image(systemName: "checkmark")
                                .foregroundColor(SpotifyySettingsView.spotifyAccentColor)
                        }
                    }
                    .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())
            }

            Section {
                Toggle(isOn: Binding(
                    get: { options.showToast },
                    set: { newValue in
                        var updated = options
                        updated.showToast = newValue
                        options = updated
                        UserDefaults.sleepTimerOptions = updated
                    }
                )) {
                    Text("sleep_timer_show_toast".localized)
                }
            }

            SpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: armed)
        .onReceive(ticker) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .spotifyySleepTimerChanged)) { _ in refresh() }
        .onAppear(perform: refresh)
    }

    // MARK: - Rows

    private var statusRow: some View {
        HStack(spacing: 14) {
            Image(systemName: armed ? "hourglass" : "moon.zzz.fill")
                .font(.system(size: 18))
                .foregroundColor(armed ? SpotifyySettingsView.spotifyAccentColor : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 16, weight: .semibold))
                Text(statusDetail)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func presetRow(_ minutes: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "clock")
                .font(.system(size: 16))
                .foregroundColor(SpotifyySettingsView.spotifyAccentColor)
                .frame(width: 26)

            Text("sleep_timer_minutes".localizeWithFormat(String(minutes)))
                .foregroundColor(.white)

            Spacer()

            if isCountingDown(to: minutes) {
                Image(systemName: "checkmark")
                    .foregroundColor(SpotifyySettingsView.spotifyAccentColor)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Derived state

    private var isCountingDown: Bool { armed && mode == .countdown }
    private var isWaitingForTrackEnd: Bool { armed && mode == .endOfTrack }

    private func isCountingDown(to minutes: Int) -> Bool {
        isCountingDown && options.lastUsedMinutes == minutes
    }

    private var statusTitle: String {
        if isWaitingForTrackEnd { return "sleep_timer_waiting_for_track".localized }
        guard armed else { return "sleep_timer_idle".localized }
        return "sleep_timer_remaining".localizeWithFormat(countdownText)
    }

    private var statusDetail: String {
        isWaitingForTrackEnd
            ? "sleep_timer_end_of_track_description".localized
            : "sleep_timer_footer_short".localized
    }

    private var countdownText: String {
        guard let remaining = remaining else { return "--:--" }
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func refresh() {
        let controller = SleepTimerController.shared
        armed = controller.isActive
        mode = controller.activeMode
        remaining = controller.remainingSeconds
        options = UserDefaults.sleepTimerOptions
    }
}
