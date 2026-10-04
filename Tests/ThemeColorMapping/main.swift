import Foundation

/// Standalone checks for `IayxifyThemeColorMap` — the part of the theming system
/// that has no UIKit dependency, so CI can compile and run it directly with
/// `swiftc Sources/Iayxify/Appearance/IayxifyThemeColorMap.swift Tests/ThemeColorMapping/main.swift`.
///
/// These tests pin down the rules the on-device engine relies on: Spotify's own
/// tokens map to the theme, content colours pass through, translucent colours
/// are never touched, near-miss greys still map, and Dark mode leaves Spotify's
/// palette alone.

func writeDebugLog(_ message: String) { }

var failures = 0

func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok   \(label)")
    } else {
        failures += 1
        print("  FAIL \(label)")
    }
}

func rgb(_ hex: String) -> IayxifyRGB {
    guard let color = IayxifyRGB(hex: hex) else {
        fatalError("test bug: unparsable hex \(hex)")
    }
    return color
}

let mocha = IayxifyThemeColorMap.palette(theme: .mocha, custom: IayxifyCustomThemeHex())
let ocean = IayxifyThemeColorMap.palette(theme: .ocean, custom: IayxifyCustomThemeHex())
let dark = IayxifyThemeColorMap.palette(theme: .dark, custom: IayxifyCustomThemeHex())

print("hex parsing")
expect(IayxifyRGB(hex: "#1ED760") == IayxifyRGB(red: 0x1E, green: 0xD7, blue: 0x60), "#RRGGBB parses")
expect(IayxifyRGB(hex: "1ED760") == IayxifyRGB(red: 0x1E, green: 0xD7, blue: 0x60), "bare RRGGBB parses")
expect(IayxifyRGB(hex: "#1D6") == IayxifyRGB(red: 0x11, green: 0xDD, blue: 0x66), "#RGB expands")
expect(IayxifyRGB(hex: "#11223344")?.alpha == 0x44, "8-digit form keeps alpha")
expect(IayxifyRGB(hex: "not a colour") == nil, "garbage rejected")
expect(rgb("#1ED760").hex == "#1ED760", "hex round-trips")

print("spotify tokens map onto the theme")
expect(IayxifyThemeColorMap.mapped(rgb("#121212"), to: mocha) == mocha.background, "#121212 -> theme background")
expect(IayxifyThemeColorMap.mapped(rgb("#000000"), to: mocha) == mocha.background, "#000000 -> theme background")
expect(IayxifyThemeColorMap.mapped(rgb("#1F1F1F"), to: mocha) == mocha.card, "#1F1F1F -> theme card")
expect(IayxifyThemeColorMap.mapped(rgb("#242424"), to: mocha) == mocha.card, "#242424 -> theme card")
expect(IayxifyThemeColorMap.mapped(rgb("#FFFFFF"), to: mocha) == mocha.primaryText, "white text -> theme text")
expect(IayxifyThemeColorMap.mapped(rgb("#A7A7A7"), to: mocha) == mocha.secondaryText, "secondary text -> theme secondary")
expect(IayxifyThemeColorMap.mapped(rgb("#1DB954"), to: mocha) == mocha.accent, "old Spotify green -> theme accent")
expect(IayxifyThemeColorMap.mapped(rgb("#1ED760"), to: ocean) == ocean.accent, "current Spotify green -> theme accent")

print("content colours pass through")
expect(IayxifyThemeColorMap.mapped(rgb("#E13332"), to: mocha) == nil, "album-art red untouched")
expect(IayxifyThemeColorMap.mapped(rgb("#4B2E83"), to: mocha) == nil, "album-art purple untouched")
expect(IayxifyThemeColorMap.mapped(rgb("#00A0FF"), to: mocha) == nil, "saturated blue untouched")
expect(IayxifyThemeColorMap.mapped(IayxifyRGB(red: 255, green: 255, blue: 255, alpha: 128), to: mocha) == nil, "translucent white untouched")
expect(IayxifyThemeColorMap.mapped(IayxifyRGB(red: 0, green: 0, blue: 0, alpha: 0), to: mocha) == nil, "clear untouched")

print("near-miss greys still map")
expect(IayxifyThemeColorMap.mapped(rgb("#101010"), to: mocha) == mocha.background, "#101010 -> theme background")
expect(IayxifyThemeColorMap.mapped(rgb("#EBEBEB"), to: mocha) == mocha.primaryText, "#EBEBEB -> theme text")
expect(IayxifyThemeColorMap.mapped(rgb("#0D0D0D"), to: mocha) == mocha.background, "#0D0D0D -> theme background")
expect(IayxifyThemeColorMap.mapped(rgb("#2B2B2B"), to: mocha) == mocha.separator, "#2B2B2B -> theme separator")

print("idempotency")
expect(IayxifyThemeColorMap.mapped(mocha.background, to: mocha) == nil, "theme colour is not remapped again")

print("dark mode leaves spotify's palette alone")
expect(IayxifyThemeColorMap.mapped(rgb("#121212"), to: dark) == nil, "dark background unchanged")
expect(IayxifyThemeColorMap.mapped(rgb("#1F1F1F"), to: dark) == nil, "dark card unchanged")
expect(IayxifyThemeColorMap.mapped(rgb("#FFFFFF"), to: dark) == nil, "dark text unchanged")
expect(IayxifyThemeColorMap.mapped(rgb("#A7A7A7"), to: dark) == nil, "dark secondary text unchanged")
expect(IayxifyThemeColorMap.mapped(rgb("#1ED760"), to: dark) == nil, "dark accent unchanged")

print("custom theme")
let custom = IayxifyCustomThemeHex(
    accentHex: "#00FF88",
    backgroundHex: "#001100",
    cardHex: "#002200",
    prefersDarkAppearance: true
)
let customPalette = IayxifyThemeColorMap.palette(theme: .custom, custom: custom)
expect(customPalette.accent == rgb("#00FF88"), "custom accent used")
expect(customPalette.background == rgb("#001100"), "custom background used")
expect(customPalette.card == rgb("#002200"), "custom card used")
expect(customPalette.onAccent == rgb("#000000"), "on-accent contrast derived")
expect(customPalette.isDark, "custom dark flag carried")

let brokenCustom = IayxifyCustomThemeHex(
    accentHex: "zzz",
    backgroundHex: "",
    cardHex: "#123456",
    prefersDarkAppearance: false
)
let brokenPalette = IayxifyThemeColorMap.palette(theme: .custom, custom: brokenCustom)
expect(brokenPalette.background == rgb("#0B0508"), "unparsable background falls back")
expect(brokenPalette.accent == rgb("#FF4E8E"), "unparsable accent falls back")
expect(!brokenPalette.isDark, "custom light flag carried")

print("presets are distinct")
var signatures: [String] = []
for theme in IayxifyThemeID.allCases where theme != .custom {
    let palette = IayxifyThemeColorMap.palette(theme: theme, custom: IayxifyCustomThemeHex())
    signatures.append("\(palette.accent.hex)/\(palette.background.hex)")
    expect(palette.accent.isOpaque, "\(theme.rawValue) accent is opaque")
    expect(palette.primaryText != palette.background, "\(theme.rawValue) text contrasts background")
}
// Light and Dark share Spotify green on purpose, so the accent+background pair
// is what identifies a preset.
expect(
    Set(signatures).count == signatures.count,
    "no two presets share an accent+background pair"
)

if failures == 0 {
    print("theme colour mapping: all checks passed")
    exit(0)
} else {
    print("theme colour mapping: \(failures) check(s) failed")
    exit(1)
}
