import SwiftUI
import UIKit

/// Theme picker for Iayxify's own screens.
///
/// Every theme carries an appearance style, an accent and a background/card
/// pair, so switching to Mocha or Pink Dark recolours the screens rather than
/// just one highlight. The choice is stored in `UserDefaults.appearanceThemeOptions`
/// and read back by `SpotifyySettingsView.spotifyAccentColor` plus
/// `SpotifyySettingsViewController`, which themes the screens it hosts.
struct SpotifyyAppearanceSettingsView: View {
    @State private var options = UserDefaults.appearanceThemeOptions

    private var palette: IayxifyPalette {
        options.theme.palette(custom: options.custom)
    }

    var body: some View {
        List {
            Section(
                header: Text("theme_section".localized),
                footer: Text("theme_footer".localized)
            ) {
                ForEach(IayxifyTheme.allCases, id: \.self) { theme in
                    Button {
                        select(theme)
                    } label: {
                        themeRow(theme)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if options.theme.isCustom {
                Section(
                    header: Text("theme_custom_section".localized),
                    footer: Text("theme_custom_footer".localized)
                ) {
                    colorRow(
                        titleKey: "theme_custom_accent",
                        hex: options.custom.accentHex
                    ) { hex in
                        options.custom.accentHex = hex
                        commitCustom()
                    }

                    colorRow(
                        titleKey: "theme_custom_background",
                        hex: options.custom.backgroundHex
                    ) { hex in
                        options.custom.backgroundHex = hex
                        commitCustom()
                    }

                    colorRow(
                        titleKey: "theme_custom_card",
                        hex: options.custom.cardHex
                    ) { hex in
                        options.custom.cardHex = hex
                        commitCustom()
                    }

                    Toggle(isOn: Binding(
                        get: { options.custom.prefersDarkAppearance },
                        set: { newValue in
                            options.custom.prefersDarkAppearance = newValue
                            commitCustom()
                        }
                    )) {
                        Text("theme_custom_dark".localized)
                    }
                }
            }

            Section(
                header: Text("theme_extras_section".localized),
                footer: Text("theme_extras_footer".localized)
            ) {
                Toggle(isOn: Binding(
                    get: { options.rainbowPremiumName },
                    set: { newValue in
                        options.rainbowPremiumName = newValue
                        commit(debounced: false)
                    }
                )) {
                    Text("theme_option_rainbow".localized)
                }

                Toggle(isOn: Binding(
                    get: { options.premiumPageSettingsEntry },
                    set: { newValue in
                        options.premiumPageSettingsEntry = newValue
                        commit(debounced: false)
                    }
                )) {
                    Text("theme_option_premium_entry".localized)
                }

                Toggle(isOn: Binding(
                    get: { options.applyTintToSpotifyControls },
                    set: { newValue in
                        options.applyTintToSpotifyControls = newValue
                        commit(debounced: false)
                    }
                )) {
                    Text("theme_option_tint".localized)
                }
            }

            Section(header: Text("theme_preview_section".localized)) {
                preview
            }

            if !isDefault {
                Section {
                    Button {
                        reset()
                    } label: {
                        Text("theme_reset".localized)
                            .foregroundColor(.red)
                    }
                }
            }

            SpacerView()
        }
        .listStyle(GroupedListStyle())
    }

    // MARK: - Rows

    private func themeRow(_ theme: IayxifyTheme) -> some View {
        let themePalette = theme.palette(custom: options.custom)

        return HStack(spacing: 14) {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [themePalette.background, themePalette.accent]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.localizationKey.localized)
                    .foregroundColor(.primary)

                Text(theme.subtitleKey.localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if options.theme == theme {
                Image(systemName: "checkmark")
                    .foregroundColor(palette.accent)
            }
        }
        .contentShape(Rectangle())
    }

    /// `ColorPicker` needs a `Color` binding, but the choice is persisted as a
    /// hex string like the built-in themes, so it round-trips through the same
    /// codable payload.
    private func colorRow(
        titleKey: String,
        hex: String,
        onChange: @escaping (String) -> Void
    ) -> some View {
        ColorPicker(
            titleKey.localized,
            selection: Binding(
                get: { Color(hex: hex) },
                set: { newValue in onChange("#" + newValue.hexString) }
            ),
            supportsOpacity: false
        )
    }

    /// Fake Spotify-ish controls drawn in the selected theme, so the effect is
    /// visible without leaving the screen.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(palette.accent)
                Text("theme_preview_row".localized)
                    .foregroundColor(palette.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }

            bar

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.card)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(palette.accent)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("theme_preview_card".localized)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    Text(palette.accent.hexString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack {
                Text("theme_preview_toggle".localized)
                Spacer()
                ZStack(alignment: .trailing) {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 51, height: 31)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 27, height: 27)
                        .padding(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Same shape as the listening-stats bar, so the preview matches real rows.
    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(palette.accent)
                    .frame(width: max(2, proxy.size.width * 0.55))
            }
        }
        .frame(height: 5)
    }

    // MARK: - State

    private var isDefault: Bool {
        options.theme == .dark
            && options.applyTintToSpotifyControls
            && options.rainbowPremiumName
            && options.premiumPageSettingsEntry
    }

    private func select(_ theme: IayxifyTheme) {
        options.theme = theme
        commit(debounced: false)
    }

    private func commitCustom() {
        commit(debounced: true)
    }

    private func reset() {
        options = SpotifyyAppearanceOptions()
        UserDefaults.appearanceThemeOptions = options
        SpotifyyAppearance.applyToSystemControls()
        SpotifyyAppearance.refreshScreenAppearance()
        SpotifyyAppearance.notifyChanged(debounced: false)
    }

    private func commit(debounced: Bool) {
        UserDefaults.appearanceThemeOptions = options
        SpotifyyAppearance.applyToSystemControls()
        SpotifyyAppearance.refreshScreenAppearance()
        SpotifyyAppearance.notifyChanged(debounced: debounced)
    }
}
