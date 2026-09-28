import Foundation
import SwiftUI
import UIKit

/// Full look-and-feel presets.
///
/// Replaces the old accent-only picker: a theme now owns the appearance style
/// (light/dark), the accent, and the background/card colours of Iayxify's own
/// screens, so "Pink Light", "Mocha", etc. actually look like a theme instead of
/// one recoloured highlight.
///
/// `rawValue` is persisted, so cases must not be renamed — add new ones instead.
enum IayxifyTheme: String, CaseIterable, Codable {
    case light
    case dark
    case mocha
    case pinkLight
    case pinkDark
    case ocean
    case custom

    /// Localization key for the picker row label. Resolved through
    /// `BundleHelper` with an English fallback, like every other key.
    ///
    /// Spelled out instead of interpolating `rawValue` so `Tools/l10n_lint.py`
    /// can see every key as a literal, and a typo can't hide behind a dynamic key.
    var localizationKey: String {
        switch self {
        case .light: return "theme_light"
        case .dark: return "theme_dark"
        case .mocha: return "theme_mocha"
        case .pinkLight: return "theme_pinkLight"
        case .pinkDark: return "theme_pinkDark"
        case .ocean: return "theme_ocean"
        case .custom: return "theme_custom"
        }
    }

    /// Short line shown under the name in the picker.
    var subtitleKey: String {
        switch self {
        case .light: return "theme_light_subtitle"
        case .dark: return "theme_dark_subtitle"
        case .mocha: return "theme_mocha_subtitle"
        case .pinkLight: return "theme_pinkLight_subtitle"
        case .pinkDark: return "theme_pinkDark_subtitle"
        case .ocean: return "theme_ocean_subtitle"
        case .custom: return "theme_custom_subtitle"
        }
    }

    /// Whether the custom colour pickers apply. Drives the "Custom colours"
    /// section in the picker.
    var isCustom: Bool { self == .custom }

    func palette(custom: SpotifyyCustomTheme) -> IayxifyPalette {
        switch self {
        case .light:
            return IayxifyPalette(
                accent: Color(hex: "#1ED760"),
                background: Color(hex: "#FFFFFF"),
                card: Color(hex: "#F2F2F7"),
                style: .light
            )
        case .dark:
            return IayxifyPalette(
                accent: Color(hex: "#1ED760"),
                background: Color(hex: "#121212"),
                card: Color(hex: "#1C1C1E"),
                style: .dark
            )
        case .mocha:
            // Catppuccin Mocha: mauve accent on the base/base-mantle greys.
            return IayxifyPalette(
                accent: Color(hex: "#CBA6F7"),
                background: Color(hex: "#1E1E2E"),
                card: Color(hex: "#313244"),
                style: .dark
            )
        case .pinkLight:
            return IayxifyPalette(
                accent: Color(hex: "#FF4E8E"),
                background: Color(hex: "#FFF5F8"),
                card: Color(hex: "#FFFFFF"),
                style: .light
            )
        case .pinkDark:
            return IayxifyPalette(
                accent: Color(hex: "#FF4E8E"),
                background: Color(hex: "#0B0508"),
                card: Color(hex: "#1A1015"),
                style: .dark
            )
        case .ocean:
            return IayxifyPalette(
                accent: Color(hex: "#27C7E0"),
                background: Color(hex: "#041C2C"),
                card: Color(hex: "#0B2A3D"),
                style: .dark
            )
        case .custom:
            return IayxifyPalette(
                accent: Color(hex: custom.accentHex),
                background: Color(hex: custom.backgroundHex),
                card: Color(hex: custom.cardHex),
                style: custom.prefersDarkAppearance ? .dark : .light
            )
        }
    }
}

/// The resolved colours of a theme. Plain values so the picker can render any
/// theme's swatch without switching to it first.
struct IayxifyPalette {
    var accent: Color
    var background: Color
    var card: Color
    var style: UIUserInterfaceStyle
}

/// Everything the "Custom" theme lets you set.
struct SpotifyyCustomTheme: Codable, Equatable {
    var accentHex: String = "#FF4E8E"
    var backgroundHex: String = "#0B0508"
    var cardHex: String = "#1A1015"
    /// Custom themes are dark by default; light colours need the light style or
    /// text stays white-on-white.
    var prefersDarkAppearance: Bool = true
}

struct SpotifyyAppearanceOptions: Codable {
    var theme: IayxifyTheme = .dark
    var custom = SpotifyyCustomTheme()

    /// Re-tints views that Spotify creates *after* this is set through the
    /// `UIView` appearance proxy. Defaults to on because entering Iayxify
    /// settings already forced Spotify green globally; keeping it on means no
    /// behaviour change for users who never open the theme screen.
    var applyTintToSpotifyControls: Bool = true

    /// Paints the animated rainbow over the Iayxify name on Spotify's
    /// "Your Premium" page.
    var rainbowPremiumName: Bool = true

    /// Adds the "Iayxify Settings" entry to that same page.
    var premiumPageSettingsEntry: Bool = true

    /// Adds an "Iayxify Settings" row to Spotify's side drawer, next to
    /// Settings and privacy. That panel is the usual way in, so this defaults to
    /// on even though the Your Premium page entry exists as well.
    var showSideDrawerEntry: Bool = true

    /// Hand-written so a blob written by an older build (missing the newer
    /// keys) still decodes instead of silently resetting the user's theme.
    init() { }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = (try? container.decode(IayxifyTheme.self, forKey: .theme)) ?? .dark
        custom = (try? container.decode(SpotifyyCustomTheme.self, forKey: .custom)) ?? SpotifyyCustomTheme()
        applyTintToSpotifyControls =
            (try? container.decode(Bool.self, forKey: .applyTintToSpotifyControls)) ?? true
        rainbowPremiumName =
            (try? container.decode(Bool.self, forKey: .rainbowPremiumName)) ?? true
        premiumPageSettingsEntry =
            (try? container.decode(Bool.self, forKey: .premiumPageSettingsEntry)) ?? true
        showSideDrawerEntry =
            (try? container.decode(Bool.self, forKey: .showSideDrawerEntry)) ?? true
    }
}

extension UserDefaults {
    @UserDefault(key: "appearanceThemeOptions", defaultValue: SpotifyyAppearanceOptions())
    static var appearanceThemeOptions
}

extension Notification.Name {
    /// Posted after the theme changes so already-visible screens can refresh.
    static let spotifyyAppearanceChanged = Notification.Name("SpotifyyAppearanceChanged")
}

/// Reads the persisted theme and pushes it into UIKit.
///
/// Split in two halves on purpose:
/// - `applyToSystemControls()` is global and cheap — called from the settings
///   screens' `init` so views Spotify builds *afterwards* pick up the accent.
/// - `enterThemedScreen()` / `leaveThemedScreen()` bracket Iayxify's own
///   screens (called by `SpotifyySettingsViewController`) and are the only
///   place that recolours list backgrounds, so Spotify's own UI is left alone
///   once the user leaves.
enum SpotifyyAppearance {
    static let spotifyGreenHex = "#1ED760"

    /// Colour written into Spotify's own plan/badge payloads. A fixed
    /// magenta-pink that reads on light and dark Spotify, so the plan row still
    /// looks deliberate if the animated rainbow can't be applied (Spotify draws
    /// some of these names with SwiftUI text, which has no `UILabel` to mask).
    static let planAccentHex = "#FF6AC1"

    static var options: SpotifyyAppearanceOptions { UserDefaults.appearanceThemeOptions }

    static var theme: IayxifyTheme { options.theme }

    static var palette: IayxifyPalette {
        let options = options
        return options.theme.palette(custom: options.custom)
    }

    /// The colour every Iayxify screen uses for its accent.
    ///
    /// Computed on each read — it decodes a tiny JSON blob — so the picker takes
    /// effect immediately without invalidating the existing call sites.
    static var accentColor: Color { palette.accent }

    /// Background of Iayxify's own screens.
    static var screenBackground: Color { palette.background }

    /// Row colour in Iayxify's own screens.
    static var cardBackground: Color { palette.card }

    // MARK: - Global tint

    /// Points Spotify's UIKit appearance proxy at the theme accent (or back at
    /// Spotify green when the tint option is off). Spotify only re-reads the
    /// proxy for views it creates afterwards, so this is a best-effort nudge.
    static func applyToSystemControls() {
        let options = options
        let tint = options.applyTintToSpotifyControls
            ? options.theme.palette(custom: options.custom).accent
            : Color(hex: spotifyGreenHex)
        UIView.appearance().tintColor = UIColor(tint)
    }

    // MARK: - Screen theming

    /// Nested screens push on top of each other, so the background stays themed
    /// until the last one is gone.
    private static var themedScreenDepth = 0

    /// Called from `viewWillAppear` of every Iayxify screen, before the
    /// navigation push animates — so the views Spotify builds for the incoming
    /// screen already see the themed appearance proxies.
    static func enterThemedScreen() {
        themedScreenDepth += 1
        applyScreenAppearance()
    }

    static func leaveThemedScreen() {
        themedScreenDepth = max(0, themedScreenDepth - 1)
        guard themedScreenDepth == 0 else { return }
        resetScreenAppearance()
    }

    /// Re-applies the current theme to screens that are already open. Needed
    /// when the theme changes while a themed screen is visible — the appearance
    /// proxies only affect views created afterwards.
    static func refreshScreenAppearance() {
        guard themedScreenDepth > 0 else { return }
        applyScreenAppearance()
    }

    // MARK: - Change notification

    private static var pendingNotification: DispatchWorkItem?

    /// Tells open screens the theme changed. Debounced by default because a
    /// colour picker drag emits a change on every tick, and each notification
    /// rebuilds the settings root underneath.
    static func notifyChanged(debounced: Bool = true, delay: TimeInterval = 0.35) {
        guard debounced else {
            pendingNotification?.cancel()
            pendingNotification = nil
            post()
            return
        }

        pendingNotification?.cancel()
        let work = DispatchWorkItem { post() }
        pendingNotification = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func post() {
        pendingNotification = nil
        NotificationCenter.default.post(name: .spotifyyAppearanceChanged, object: nil)
    }

    private static func applyScreenAppearance() {
        let palette = palette

        WindowHelper.shared.overrideUserInterfaceStyle(palette.style)

        let background = UIColor(palette.background)
        let card = UIColor(palette.card)

        // SwiftUI's List is a table view (grouped style) or a collection view
        // depending on the iOS version, and the cells are what actually cover
        // the screen — so all four classes need the colour.
        UITableView.appearance().backgroundColor = background
        UICollectionView.appearance().backgroundColor = background
        UITableViewCell.appearance().backgroundColor = card
        UICollectionViewCell.appearance().backgroundColor = card
    }

    private static func resetScreenAppearance() {
        // Hand the window's appearance back to Spotify instead of leaving the
        // user's theme forced onto their own app.
        WindowHelper.shared.overrideUserInterfaceStyle(.unspecified)

        UITableView.appearance().backgroundColor = nil
        UICollectionView.appearance().backgroundColor = nil
        UITableViewCell.appearance().backgroundColor = nil
        UICollectionViewCell.appearance().backgroundColor = nil
    }
}
