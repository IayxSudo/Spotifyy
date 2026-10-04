import SwiftUI
import UIKit

/// One theme = one look for the whole app.
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

    /// The value-level identifier the colour map works with.
    var id: IayxifyThemeID {
        IayxifyThemeID(rawValue: rawValue) ?? .dark
    }

    /// Localization key for the picker row label.
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

    /// Whether the custom colour pickers apply.
    var isCustom: Bool { self == .custom }

    func palette(custom: IayxifyCustomTheme) -> IayxifyPalette {
        IayxifyPalette(IayxifyThemeColorMap.palette(theme: id, custom: custom.hex))
    }
}

/// Everything the "Custom" theme lets you set.
struct IayxifyCustomTheme: Codable, Equatable {
    var accentHex: String = "#FF4E8E"
    var backgroundHex: String = "#0B0508"
    var cardHex: String = "#1A1015"
    /// Custom themes are dark by default; light colours need the light style or
    /// text stays white-on-white.
    var prefersDarkAppearance: Bool = true

    var hex: IayxifyCustomThemeHex {
        IayxifyCustomThemeHex(
            accentHex: accentHex,
            backgroundHex: backgroundHex,
            cardHex: cardHex,
            prefersDarkAppearance: prefersDarkAppearance
        )
    }
}

/// A resolved theme as SwiftUI/UIKit values.
struct IayxifyPalette {
    var accent: Color
    var background: Color
    var card: Color
    var elevated: Color
    var primaryText: Color
    var secondaryText: Color
    var separator: Color
    var onAccent: Color
    var style: UIUserInterfaceStyle

    init(_ hex: IayxifyPaletteHex) {
        accent = Color(hex: hex.accent.hex)
        background = Color(hex: hex.background.hex)
        card = Color(hex: hex.card.hex)
        elevated = Color(hex: hex.elevated.hex)
        primaryText = Color(hex: hex.primaryText.hex)
        secondaryText = Color(hex: hex.secondaryText.hex)
        separator = Color(hex: hex.separator.hex)
        onAccent = Color(hex: hex.onAccent.hex)
        style = hex.isDark ? .dark : .light
    }
}

struct IayxifyAppearanceOptions: Codable {
    var theme: IayxifyTheme = .dark
    var custom = IayxifyCustomTheme()

    /// Repaint Spotify's own chrome with the theme. This is what makes a theme
    /// reach the whole app; Dark is exempt because it *is* Spotify's own look.
    var themeSpotifyApp: Bool = true

    /// Points UIKit's tint at the theme accent instead of Spotify green.
    var applyTintToSpotifyControls: Bool = true

    /// Paints the animated rainbow over the Iayxify name on Spotify's
    /// "Your Premium" name and badge.
    var rainbowPremiumName: Bool = true

    /// Adds the "Iayxify Settings" entry to the "Your Premium" page.
    var premiumPageSettingsEntry: Bool = true

    /// Adds an "Iayxify Settings" row to Spotify's side drawer.
    var showSideDrawerEntry: Bool = true

    /// Hand-written so a blob written by an older build (missing the newer
    /// keys) still decodes instead of silently resetting the user's theme.
    init() { }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = (try? container.decode(IayxifyTheme.self, forKey: .theme)) ?? .dark
        custom = (try? container.decode(IayxifyCustomTheme.self, forKey: .custom)) ?? IayxifyCustomTheme()
        themeSpotifyApp = (try? container.decode(Bool.self, forKey: .themeSpotifyApp)) ?? true
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
    @UserDefault(key: "appearanceThemeOptions", defaultValue: IayxifyAppearanceOptions())
    static var appearanceThemeOptions
}

extension Notification.Name {
    /// Posted after the theme changes so already-visible screens can refresh.
    static let iayxifyAppearanceChanged = Notification.Name("IayxifyAppearanceChanged")
}

/// The single place that answers "what does the theme look like right now?", so
/// every screen, the theme engine and the entry points agree on one palette.
enum IayxifyAppearance {
    static let spotifyGreenHex = IayxifyThemeColorMap.spotifyGreenHex

    /// Colour written into Spotify's own plan/badge payloads. A fixed
    /// magenta-pink that reads on light and dark Spotify, so the plan row still
    /// looks deliberate if the animated rainbow can't be applied.
    static let planAccentHex = "#FF6AC1"

    static var options: IayxifyAppearanceOptions { UserDefaults.appearanceThemeOptions }

    static var theme: IayxifyTheme { options.theme }

    /// The resolved palette, in plain values (the engine works on these)…
    static var paletteHex: IayxifyPaletteHex {
        IayxifyThemeColorMap.palette(theme: theme.id, custom: options.custom.hex)
    }

    /// …and as SwiftUI colours for the settings screens.
    static var palette: IayxifyPalette { IayxifyPalette(paletteHex) }

    /// The colour every Iayxify screen uses for its accent.
    static var accentColor: Color { palette.accent }

    /// Background of Iayxify's own screens.
    static var screenBackground: Color { palette.background }

    /// Row colour in Iayxify's own screens.
    static var cardBackground: Color { palette.card }

    /// Whether Spotify's own chrome should be repainted right now.
    ///
    /// Dark is a no-op by design: it is Spotify's own palette, so remapping it
    /// would only churn the hierarchy for a near-identical result.
    static var remapsSpotifyApp: Bool {
        options.themeSpotifyApp && theme != .dark
    }

    /// True while an Iayxify screen is on top. When the user keeps the app-wide
    /// remap off, this is what still lets a light theme darken (or a dark theme
    /// lighten) the settings screens without touching Spotify.
    private(set) static var isThemedScreenVisible = false

    private static var themedScreenDepth = 0

    // MARK: - Global tint

    /// Points UIKit's appearance proxy at the theme accent (or back at Spotify
    /// green when the tint option is off). Only affects views created
    /// afterwards; the engine's swizzles catch everything else.
    static func applyToSystemControls() {
        let tint = options.applyTintToSpotifyControls
            ? UIColor(palette.accent)
            : UIColor(Color(hex: spotifyGreenHex))

        UIView.appearance().tintColor = tint
        UINavigationBar.appearance().tintColor = tint
        UITabBar.appearance().tintColor = tint
    }

    // MARK: - Screen bracketing

    /// Called from `viewWillAppear` of every Iayxify screen, before the push
    /// animates, so the incoming screen and the window already carry the theme.
    static func enterThemedScreen() {
        themedScreenDepth += 1
        isThemedScreenVisible = themedScreenDepth > 0
        IayxifyThemeEngine.shared.refresh(repaint: true)
    }

    static func leaveThemedScreen() {
        themedScreenDepth = max(0, themedScreenDepth - 1)
        isThemedScreenVisible = themedScreenDepth > 0
        // An app-wide theme stays on for the rest of the app; only the
        // Iayxify-screens-only mode gives the window back to Spotify here.
        IayxifyThemeEngine.shared.refresh(repaint: true)
    }

    /// Re-applies the current theme. Needed when the theme changes while a
    /// themed screen is visible — the appearance proxies only affect views
    /// created afterwards.
    static func refreshScreenAppearance() {
        IayxifyThemeEngine.shared.refresh(repaint: true)
    }

    // MARK: - Change notification

    private static var pendingNotification: DispatchWorkItem?

    /// Tells open screens the theme changed. Debounced by default because a
    /// colour picker drag emits a change on every tick.
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
        NotificationCenter.default.post(name: .iayxifyAppearanceChanged, object: nil)
    }
}
