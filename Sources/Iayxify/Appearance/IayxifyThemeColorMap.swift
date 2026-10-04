import Foundation

/// Pure colour maths behind the app-wide theme engine.
///
/// Deliberately UIKit/SwiftUI free: this is the half of the theming system that
/// CI can exercise with a plain `swiftc` build (`Tests/ThemeColorMapping`), where
/// no app target is available. Everything here is values in, values out — no
/// view hierarchy, no appearance proxies.

// MARK: - Colours

/// A colour as straight 8-bit sRGB components.
struct IayxifyRGB: Hashable, Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RRGGBB`, `RRGGBB`, `#RGB` or `#RRGGBBAA`.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }

        guard let raw = UInt64(value, radix: 16) else { return nil }

        switch value.count {
        case 6:
            self.init(
                red: UInt8((raw >> 16) & 0xFF),
                green: UInt8((raw >> 8) & 0xFF),
                blue: UInt8(raw & 0xFF)
            )
        case 8:
            self.init(
                red: UInt8((raw >> 24) & 0xFF),
                green: UInt8((raw >> 16) & 0xFF),
                blue: UInt8((raw >> 8) & 0xFF),
                alpha: UInt8(raw & 0xFF)
            )
        default:
            return nil
        }
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var isOpaque: Bool { alpha == 255 }

    /// Rec. 601 brightness, 0...1.
    var luminance: Double {
        (0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)) / 255.0
    }

    /// Distance between the brightest and darkest channel, 0...255.
    var channelSpread: Int {
        let values = [Int(red), Int(green), Int(blue)]
        return (values.max() ?? 0) - (values.min() ?? 0)
    }

    /// True for greys and near-greys — what Spotify's own chrome is made of.
    /// Album art and extracted content colours are saturated and fail this.
    var isGrayscale: Bool { channelSpread <= 8 }

    func isNear(_ other: IayxifyRGB, tolerance: Int = 6) -> Bool {
        abs(Int(red) - Int(other.red)) <= tolerance
            && abs(Int(green) - Int(other.green)) <= tolerance
            && abs(Int(blue) - Int(other.blue)) <= tolerance
            && alpha == other.alpha
    }

    /// Linear blend towards `other`, used to derive helper shades.
    func mixed(with other: IayxifyRGB, amount: Double) -> IayxifyRGB {
        let t = min(max(amount, 0), 1)
        func channel(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8(min(max(Double(a) * (1 - t) + Double(b) * t, 0), 255))
        }
        return IayxifyRGB(
            red: channel(red, other.red),
            green: channel(green, other.green),
            blue: channel(blue, other.blue),
            alpha: alpha
        )
    }

    func lighter(by amount: Double) -> IayxifyRGB {
        mixed(with: IayxifyRGB(red: 255, green: 255, blue: 255), amount: amount)
    }

    func darker(by amount: Double) -> IayxifyRGB {
        mixed(with: IayxifyRGB(red: 0, green: 0, blue: 0), amount: amount)
    }

    /// Black or white, whichever reads better on top of this colour.
    var readableTextColor: IayxifyRGB {
        luminance > 0.55
            ? IayxifyRGB(red: 0, green: 0, blue: 0)
            : IayxifyRGB(red: 255, green: 255, blue: 255)
    }
}

// MARK: - Roles

/// What a Spotify colour *means*, so a theme can replace it without knowing
/// which screen asked for it.
enum IayxifyColorRole: String, CaseIterable {
    case background
    case card
    case elevated
    case primaryText
    case secondaryText
    case separator
    case accent
    case onAccent
}

// MARK: - Palettes

/// A resolved theme, as plain values.
struct IayxifyPaletteHex: Equatable {
    var background: IayxifyRGB
    var card: IayxifyRGB
    var elevated: IayxifyRGB
    var primaryText: IayxifyRGB
    var secondaryText: IayxifyRGB
    var separator: IayxifyRGB
    var accent: IayxifyRGB
    var onAccent: IayxifyRGB
    var isDark: Bool

    func color(for role: IayxifyColorRole) -> IayxifyRGB {
        switch role {
        case .background: return background
        case .card: return card
        case .elevated: return elevated
        case .primaryText: return primaryText
        case .secondaryText: return secondaryText
        case .separator: return separator
        case .accent: return accent
        case .onAccent: return onAccent
        }
    }
}

/// Persisted identifiers for the built-in presets. `rawValue` is written to
/// `UserDefaults`, so cases must not be renamed — add new ones instead.
enum IayxifyThemeID: String, CaseIterable, Codable {
    case light
    case dark
    case mocha
    case pinkLight
    case pinkDark
    case ocean
    case custom
}

/// The colour half of the custom theme, stored as hex so it round-trips
/// through the same codable payload as the presets.
struct IayxifyCustomThemeHex: Codable, Equatable {
    var accentHex: String = "#FF4E8E"
    var backgroundHex: String = "#0B0508"
    var cardHex: String = "#1A1015"
    var prefersDarkAppearance: Bool = true
}

// MARK: - Mapping

/// Spotify's own palette in, theme colours out.
enum IayxifyThemeColorMap {
    /// The green Spotify uses for play buttons, progress bars and links.
    static let spotifyGreenHex = "#1ED760"

    /// One Spotify token, as a value pair.
    private static func token(_ hex: String, _ role: IayxifyColorRole) -> (IayxifyRGB, IayxifyColorRole) {
        let color = IayxifyRGB(hex: hex) ?? IayxifyRGB(red: 0, green: 0, blue: 0)
        return (color, role)
    }

    /// Spotify's design tokens, in the roles the engine maps them to.
    ///
    /// Only values Spotify itself uses for chrome belong here: backgrounds,
    /// surfaces, text and the accent greens. Content colours (album art,
    /// campaign artwork) are deliberately absent, so they pass through.
    static let tokens: [(IayxifyRGB, IayxifyColorRole)] = [
        // Surfaces
        token("#000000", .background),
        token("#121212", .background),
        token("#181818", .card),
        token("#1F1F1F", .card),
        token("#242424", .card),
        token("#282828", .card),
        token("#2A2A2A", .separator),
        token("#333333", .elevated),
        token("#3E3E3E", .elevated),
        token("#4D4D4D", .elevated),
        token("#535353", .elevated),
        // Text
        token("#FFFFFF", .primaryText),
        token("#E8E8E8", .primaryText),
        token("#D9D9D9", .primaryText),
        token("#C1C1C1", .secondaryText),
        token("#B3B3B3", .secondaryText),
        token("#A7A7A7", .secondaryText),
        token("#7F7F7F", .secondaryText),
        token("#6A6A6A", .secondaryText),
        // Accent greens
        token("#1DB954", .accent),
        token("#1ED760", .accent),
        token("#1FDF64", .accent),
    ]

    private static let exactRoles: [IayxifyRGB: IayxifyColorRole] = {
        var table: [IayxifyRGB: IayxifyColorRole] = [:]
        for (color, role) in tokens {
            table[color] = role
        }
        return table
    }()

    private static let grayTokens: [(IayxifyRGB, IayxifyColorRole)] = {
        tokens.filter { $0.0.isGrayscale }
    }()

    /// The role a Spotify colour belongs to, or nil when it is content.
    ///
    /// Exact hits are the common case. The fallback exists because the same
    /// token reaches us through colour-space conversion (P3 → sRGB) and through
    /// hand-picked near-misses like `#101010`: if the colour is a near-grey
    /// within a hair of a token's brightness, it is treated as that token.
    static func role(for color: IayxifyRGB) -> IayxifyColorRole? {
        if let exact = exactRoles[color] {
            return exact
        }

        guard color.isGrayscale else { return nil }

        // Closest wins, not first-in-table: several tokens sit within the
        // tolerance of one grey, and the nearest one is the shade it really is.
        var bestRole: IayxifyColorRole?
        var bestDelta = Double.greatestFiniteMagnitude

        for (token, role) in grayTokens {
            let delta = abs(token.luminance - color.luminance)
            guard delta <= grayLuminanceTolerance else { continue }
            if delta < bestDelta {
                bestDelta = delta
                bestRole = role
            }
        }

        return bestRole
    }

    /// How far two greys may differ in brightness and still be treated as the
    /// same token. Covers colour-space conversion and hand-picked variants.
    private static let grayLuminanceTolerance = 0.03

    /// What a Spotify colour should become under `palette`, or nil when the
    /// colour is not ours to change (content, translucency, already themed).
    static func mapped(_ color: IayxifyRGB, to palette: IayxifyPaletteHex) -> IayxifyRGB? {
        guard color.isOpaque, let role = role(for: color) else { return nil }
        let replacement = palette.color(for: role)
        return replacement == color ? nil : replacement
    }

    /// Resolves a preset (or the custom colours) into plain values.
    static func palette(theme: IayxifyThemeID, custom: IayxifyCustomThemeHex) -> IayxifyPaletteHex {
        switch theme {
        case .light:
            return IayxifyPaletteHex(
                background: rgb("#FFFFFF"),
                card: rgb("#F2F2F7"),
                elevated: rgb("#FFFFFF"),
                primaryText: rgb("#000000"),
                secondaryText: rgb("#6E6E73"),
                separator: rgb("#D1D1D6"),
                accent: rgb("#1ED760"),
                onAccent: rgb("#000000"),
                isDark: false
            )
        case .dark:
            // Spotify's own look. The token table maps onto these values almost
            // one-for-one, which is what makes "Dark" a no-op for the remap.
            return IayxifyPaletteHex(
                background: rgb("#121212"),
                card: rgb("#1F1F1F"),
                elevated: rgb("#282828"),
                primaryText: rgb("#FFFFFF"),
                secondaryText: rgb("#A7A7A7"),
                separator: rgb("#2A2A2A"),
                accent: rgb("#1ED760"),
                onAccent: rgb("#000000"),
                isDark: true
            )
        case .mocha:
            // Catppuccin Mocha: mauve accent on base/base-mantle greys.
            return IayxifyPaletteHex(
                background: rgb("#1E1E2E"),
                card: rgb("#313244"),
                elevated: rgb("#45475A"),
                primaryText: rgb("#CDD6F4"),
                secondaryText: rgb("#A6ADC8"),
                separator: rgb("#45475A"),
                accent: rgb("#CBA6F7"),
                onAccent: rgb("#1E1E2E"),
                isDark: true
            )
        case .pinkLight:
            return IayxifyPaletteHex(
                background: rgb("#FFF5F8"),
                card: rgb("#FFFFFF"),
                elevated: rgb("#FFFFFF"),
                primaryText: rgb("#2B1A22"),
                secondaryText: rgb("#7A6B72"),
                separator: rgb("#F0D7E0"),
                accent: rgb("#FF4E8E"),
                onAccent: rgb("#FFFFFF"),
                isDark: false
            )
        case .pinkDark:
            return IayxifyPaletteHex(
                background: rgb("#0B0508"),
                card: rgb("#1A1015"),
                elevated: rgb("#241820"),
                primaryText: rgb("#FFEFF5"),
                secondaryText: rgb("#B9A7AE"),
                separator: rgb("#2A1A22"),
                accent: rgb("#FF4E8E"),
                onAccent: rgb("#FFFFFF"),
                isDark: true
            )
        case .ocean:
            return IayxifyPaletteHex(
                background: rgb("#041C2C"),
                card: rgb("#0B2A3D"),
                elevated: rgb("#123C55"),
                primaryText: rgb("#E6F7FB"),
                secondaryText: rgb("#9DBDCB"),
                separator: rgb("#123C55"),
                accent: rgb("#27C7E0"),
                onAccent: rgb("#041C2C"),
                isDark: true
            )
        case .custom:
            let accent = rgb(custom.accentHex, fallback: "#FF4E8E")
            let background = rgb(custom.backgroundHex, fallback: "#0B0508")
            let card = rgb(custom.cardHex, fallback: "#1A1015")
            let text = custom.prefersDarkAppearance
                ? IayxifyRGB(red: 255, green: 255, blue: 255)
                : IayxifyRGB(red: 28, green: 27, blue: 31)
            return IayxifyPaletteHex(
                background: background,
                card: card,
                elevated: card.mixed(with: text, amount: 0.07),
                primaryText: text,
                secondaryText: text.mixed(with: background, amount: 0.35),
                separator: card.mixed(with: background, amount: 0.5),
                accent: accent,
                onAccent: accent.readableTextColor,
                isDark: custom.prefersDarkAppearance
            )
        }
    }

    private static func rgb(_ hex: String, fallback: String = "#000000") -> IayxifyRGB {
        IayxifyRGB(hex: hex) ?? IayxifyRGB(hex: fallback) ?? IayxifyRGB(red: 0, green: 0, blue: 0)
    }
}
