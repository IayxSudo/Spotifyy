import SwiftUI
import UIKit

/// Local listening statistics: what you played, how long, and how often.
/// Everything is read from SpotifyyListeningStatsStore, which lives on this
/// device only.
struct SpotifyyListeningStatsView: View {
    @State private var period: SpotifyyListeningStatsPeriod = .today
    @State private var summary = SpotifyyListeningStatsSummary.empty
    @State private var enabled = UserDefaults.listeningStatsEnabled
    @State private var isConfirmingReset = false

    private static let periods: [SpotifyyListeningStatsPeriod] = [.today, .week, .month, .allTime]

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { newValue in
                        enabled = newValue
                        UserDefaults.listeningStatsEnabled = newValue
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("listening_stats_enabled".localized)
                            .font(.system(size: 16, weight: .semibold))
                        Text("listening_stats_enabled_description".localized)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Picker("listening_stats_period".localized, selection: $period) {
                    ForEach(Self.periods, id: \.self) { candidate in
                        Text(candidate.localizedKey.localized).tag(candidate)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            Section {
                HStack(spacing: 10) {
                    statTile(
                        value: durationText(summary.seconds),
                        label: "listening_stats_total_time".localized
                    )
                    statTile(
                        value: "\(summary.plays)",
                        label: "listening_stats_total_plays".localized
                    )
                    statTile(
                        value: "\(summary.trackCount)",
                        label: "listening_stats_unique_tracks".localized
                    )
                }
            }

            if summary.isEmpty {
                Section {
                    Text("listening_stats_empty".localized)
                        .foregroundColor(.secondary)
                }
            }

            if !summary.artists.isEmpty {
                Section(header: Text("listening_stats_top_artists".localized)) {
                    rankedRows(summary.artists, fallbackLabel: "listening_stats_unknown_artist".localized)
                }
            }

            if !summary.tracks.isEmpty {
                Section(header: Text("listening_stats_top_tracks".localized)) {
                    rankedRows(summary.tracks, fallbackLabel: nil)
                }
            }

            Section(footer: Text("listening_stats_footer".localizeWithFormat(trackingSinceText))) {
                Button {
                    isConfirmingReset = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash")
                        Text("listening_stats_reset".localized)
                    }
                    .foregroundColor(.red)
                }
            }

            SpacerView()
        }
        .listStyle(GroupedListStyle())
        .animation(.default, value: summary.plays)
        .onAppear(perform: reload)
        .onChange(of: period) { _ in reload() }
        .alert(isPresented: $isConfirmingReset) {
            Alert(
                title: Text("listening_stats_reset".localized),
                message: Text("listening_stats_reset_message".localized),
                primaryButton: .destructive(Text("listening_stats_reset_confirm".localized)) {
                    SpotifyyListeningStatsStore.shared.reset()
                    reload()
                },
                secondaryButton: .cancel(Text("Cancel".uiKitLocalized))
            )
        }
    }

    // MARK: - Rows

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // Indexed rather than zipping with offsets: key paths cannot address tuple
    // elements, so `ForEach(Array(items.enumerated()), id: \.offset)` will not
    // compile.
    private func rankedRows(_ items: [SpotifyyListeningStatsRanked], fallbackLabel: String?) -> some View {
        let maximum = items.map { $0.seconds }.max() ?? 1
        return ForEach(items.indices, id: \.self) { index in
            rankedRow(items[index], index: index, maximum: maximum, fallbackLabel: fallbackLabel)
        }
    }

    private func rankedRow(_ item: SpotifyyListeningStatsRanked,
                           index: Int,
                           maximum: Double,
                           fallbackLabel: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 18, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName(item.name, fallback: fallbackLabel))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                bar(fraction: maximum > 0 ? item.seconds / maximum : 0)

                Text(detailText(item))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func bar(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(SpotifyySettingsView.spotifyAccentColor)
                    .frame(width: max(2, proxy.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 5)
    }

    // MARK: - Formatting

    private func displayName(_ name: String, fallback: String?) -> String {
        // An empty name comes from the store meaning "we never captured a
        // label for this entry"; the view decides what to show for it.
        name.isEmpty ? (fallback ?? name) : name
    }

    private func detailText(_ item: SpotifyyListeningStatsRanked) -> String {
        "listening_stats_row_detail".localizeWithFormat("\(item.plays)", durationText(item.seconds))
    }

    private func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    private var trackingSinceText: String {
        Self.dateFormatter.string(from: SpotifyyListeningStatsStore.shared.trackingStarted)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    // MARK: - Data

    private func reload() {
        summary = SpotifyyListeningStatsStore.shared.summary(for: period)
    }
}
