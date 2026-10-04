import Foundation
import ObjectiveC.runtime
import UIKit

/// Repaints Spotify's own chrome with the selected theme.
///
/// The app builds its colours in one place and applies them to views in another,
/// so the engine hooks both sides of that flow:
///
/// - **At the source.** `UIView`/`UILabel`/`CALayer` setters are swizzled and
///   the value is swapped for the theme colour when, and only when, it matches
///   one of Spotify's own design tokens (`IayxifyThemeColorMap.tokens`). Album
///   art, campaign colours and everything else passes through untouched.
/// - **Catch-up.** A view whose colour was set before the engine was installed
///   (or before the theme changed) is repainted by walking the hierarchy on each
///   screen appearance, and by a full walk whenever the theme changes.
///
/// Every remapped view remembers the Spotify colour it was given, so switching
/// themes is lossless and turning the feature off puts the app back exactly the
/// way Spotify left it.
///
/// The audit counters exist because coverage cannot be proven without a device:
/// the debug log names the colours that were skipped, so a surface that stays
/// grey can be traced to a missing token instead of guessed at.
final class IayxifyThemeEngine {
    static let shared = IayxifyThemeEngine()

    private(set) var isInstalled = false

    /// The palette currently being applied, kept as plain values so the
    /// swizzled setters never touch SwiftUI.
    private var activePalette = IayxifyThemeColorMap.palette(
        theme: .dark,
        custom: IayxifyCustomThemeHex()
    )

    /// Whether token colours are being swapped for theme colours right now.
    private var isRemapping = false

    /// Bumped whenever the palette changes, so a repaint can tell which views
    /// still need reconciling for the new theme.
    private var themeGeneration = 0

    /// Set while the engine writes colours itself, so its own writes are not
    /// mistaken for Spotify setting a fresh value.
    private var internalApplyDepth = 0

    private let backgroundKey = "IayxifyThemeOriginalBackground"
    private let textKey = "IayxifyThemeOriginalText"
    private let layerBackgroundKey = "IayxifyThemeOriginalLayerBackground"
    private let accentKey = "IayxifyThemeOriginalAccent"
    private let stampKey = "IayxifyThemeReconciledGeneration"

    // MARK: - Audit

    private var auditRemapped = 0
    private var auditSkipped: [IayxifyRGB: Int] = [:]

    private init() { }

    // MARK: - Install

    func install() {
        guard !isInstalled else { return }
        isInstalled = true

        swizzle(
            UIView.self,
            original: Selector(("setBackgroundColor:")),
            replacement: #selector(IayxifyThemeSwizzles.iayxify_setBackgroundColor(_:))
        )
        swizzle(
            UIView.self,
            original: Selector(("setTintColor:")),
            replacement: #selector(IayxifyThemeSwizzles.iayxify_setTintColor(_:))
        )
        swizzle(
            UILabel.self,
            original: Selector(("setTextColor:")),
            replacement: #selector(IayxifyThemeSwizzles.iayxify_setTextColor(_:))
        )
        swizzle(
            CALayer.self,
            original: Selector(("setBackgroundColor:")),
            replacement: #selector(IayxifyThemeSwizzles.iayxify_setLayerBackgroundColor(_:))
        )
        swizzle(
            UISwitch.self,
            original: Selector(("setOnTintColor:")),
            replacement: #selector(IayxifyThemeSwizzles.iayxify_setOnTintColor(_:))
        )
        swizzle(
            UISlider.self,
            original: Selector(("setMinimumTrackTintColor:")),
            replacement: #selector(IayxifyThemeSwizzles.iayxify_setMinimumTrackTintColor(_:))
        )
        swizzle(
            UIProgressView.self,
            original: Selector(("setProgressTintColor:")),
            replacement: #selector(IayxifyThemeSwizzles.iayxify_setProgressTintColor(_:))
        )

        NotificationCenter.default.addObserver(
            forName: .iayxifyAppearanceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(repaint: true)
        }

        refresh(repaint: false)
        writeDebugLog("[Theme] Engine installed; remapping=\(isRemapping)")
    }

    /// Swaps an implementation onto `cls`.
    ///
    /// `method_exchangeImplementations` only does the right thing when both
    /// selectors live on the same class, so the replacement selector is added to
    /// `cls` first (it normally only exists on the helper class). After the
    /// exchange, sending the replacement selector to an instance of `cls` runs
    /// the original implementation — which is exactly what the swizzled bodies
    /// rely on.
    private func swizzle(_ cls: AnyClass, original selector: Selector, replacement replacementSelector: Selector) {
        guard let originalMethod = class_getInstanceMethod(cls, selector),
              let replacementMethod = class_getInstanceMethod(IayxifyThemeSwizzles.self, replacementSelector) else {
            writeDebugLog("[Theme] Could not swizzle \(cls) \(NSStringFromSelector(selector))")
            return
        }

        let implementation = method_getImplementation(replacementMethod)
        let types = method_getTypeEncoding(replacementMethod)

        if class_addMethod(cls, replacementSelector, implementation, types),
           let added = class_getInstanceMethod(cls, replacementSelector),
           let original = class_getInstanceMethod(cls, selector) {
            method_exchangeImplementations(original, added)
        } else if let original = class_getInstanceMethod(cls, selector) {
            // The selector already exists on this class (should not happen for
            // our iayxify_* names, but never fail silently if it does).
            method_exchangeImplementations(original, replacementMethod)
        }
    }

    // MARK: - Applying

    /// Recomputes the palette from the options and, optionally, repaints what is
    /// already on screen.
    func refresh(repaint: Bool) {
        let palette = IayxifyAppearance.paletteHex
        let remap = IayxifyAppearance.remapsSpotifyApp
        let changed = palette != activePalette || remap != isRemapping

        activePalette = palette
        isRemapping = remap
        if changed {
            themeGeneration += 1
        }

        IayxifyWindowTheme.apply(palette: palette, remap: remap)

        guard repaint else { return }
        repaintAllWindows()

        if changed {
            writeDebugLog(
                "[Theme] Applied \(IayxifyAppearance.theme.rawValue); remap=\(remap); " +
                "remapped=\(auditRemapped); skipped=\(auditSkipped.count) distinct colours"
            )
            logSkippedColors()
        }
    }

    /// Repaints one subtree — used on each screen appearance.
    func repaint(_ root: UIView?) {
        guard let root = root else { return }
        reconcile(root, generation: themeGeneration, force: false)
    }

    func repaintAllWindows() {
        guard isInstalled else { return }
        auditRemapped = 0
        auditSkipped = [:]
        for window in windows() {
            reconcile(window, generation: themeGeneration, force: true)
        }
    }

    // MARK: - What the swizzled setters call

    /// The value a `backgroundColor` assignment should really use.
    func themedBackground(for object: AnyObject, color: UIColor?) -> UIColor? {
        themed(color, originalKey: backgroundKey, on: object)
    }

    /// The value a `textColor` assignment should really use.
    func themedText(for object: AnyObject, color: UIColor?) -> UIColor? {
        themed(color, originalKey: textKey, on: object)
    }

    /// The value a `tintColor`/track-colour assignment should really use.
    func themedTint(for object: AnyObject, color: UIColor?) -> UIColor? {
        themed(color, originalKey: accentKey, on: object)
    }

    func themedLayerBackground(for layer: CALayer, color: CGColor?) -> CGColor? {
        // Fast path: with remapping off (the default Dark theme), the swizzle is
        // a pass-through and nothing is bridged or looked up at all.
        guard internalApplyDepth == 0, isRemapping else { return color }

        guard let color = color else {
            objc_setAssociatedObject(layer, layerBackgroundKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return nil
        }

        let uiColor = UIColor(cgColor: color)
        guard let rgb = IayxifyRGB(color: uiColor),
              let mapped = IayxifyThemeColorMap.mapped(rgb, to: activePalette) else {
            recordSkipped(uiColor)
            objc_setAssociatedObject(layer, layerBackgroundKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return color
        }

        objc_setAssociatedObject(layer, layerBackgroundKey, color, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        auditRemapped += 1
        return UIColor(mapped).cgColor
    }

    private func themed(_ color: UIColor?, originalKey: String, on object: AnyObject) -> UIColor? {
        // Writes the engine makes itself are passed through untouched, and with
        // remapping off (the default Dark theme) so is everything else.
        guard internalApplyDepth == 0, isRemapping else { return color }

        guard let color = color else {
            objc_setAssociatedObject(object, originalKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return nil
        }

        guard let rgb = IayxifyRGB(color: color),
              let mapped = IayxifyThemeColorMap.mapped(rgb, to: activePalette) else {
            recordSkipped(color)
            objc_setAssociatedObject(object, originalKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return color
        }

        objc_setAssociatedObject(object, originalKey, color, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        auditRemapped += 1
        return UIColor(mapped)
    }

    // MARK: - Reconciliation

    private func reconcile(_ view: UIView, generation: Int, force: Bool) {
        let stamp = (objc_getAssociatedObject(view, stampKey) as? NSNumber)?.intValue
        if !force, stamp == generation {
            return
        }

        objc_setAssociatedObject(view, stampKey, NSNumber(value: generation), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        apply(to: view)

        for subview in view.subviews {
            reconcile(subview, generation: generation, force: force)
        }
    }

    /// Recomputes a single view from its stored originals.
    private func apply(to view: UIView) {
        internalApplyDepth += 1
        defer { internalApplyDepth -= 1 }

        let background = objc_getAssociatedObject(view, backgroundKey) as? UIColor
        let text = (view as? UILabel).flatMap { objc_getAssociatedObject($0, textKey) as? UIColor }
        let accent = objc_getAssociatedObject(view, accentKey) as? UIColor
        let layerBackground = objc_getAssociatedObject(view.layer, layerBackgroundKey) as? CGColor

        if isRemapping {
            if let original = background, let mapped = mapped(original) {
                view.backgroundColor = mapped
            }
            if let label = view as? UILabel, let original = text, let mapped = mapped(original) {
                label.textColor = mapped
            }
            if let original = accent, let mapped = mapped(original) {
                view.tintColor = mapped
            }
            if let original = layerBackground, let mapped = mapped(original) {
                view.layer.backgroundColor = mapped.cgColor
            }
        } else {
            // Hand the app its own colours back.
            if let original = background {
                view.backgroundColor = original
            }
            if let label = view as? UILabel, let original = text {
                label.textColor = original
            }
            if let original = accent {
                view.tintColor = original
            }
            if let original = layerBackground {
                view.layer.backgroundColor = original
            }
        }
    }

    private func mapped(_ color: UIColor) -> UIColor? {
        guard let rgb = IayxifyRGB(color: color),
              let mapped = IayxifyThemeColorMap.mapped(rgb, to: activePalette) else {
            return nil
        }
        return UIColor(mapped)
    }

    private func mapped(_ color: CGColor) -> UIColor? {
        mapped(UIColor(cgColor: color))
    }

    // MARK: - Windows

    private func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }

    // MARK: - Audit

    private func recordSkipped(_ color: UIColor) {
        guard isRemapping, let rgb = IayxifyRGB(color: color), rgb.isGrayscale else { return }
        auditSkipped[rgb, default: 0] += 1
    }

    private func logSkippedColors() {
        guard !auditSkipped.isEmpty else { return }
        var lines: [String] = []
        for (color, count) in auditSkipped.sorted(by: { $0.value > $1.value }).prefix(8) {
            lines.append("\(color.hex) x\(count)")
        }
        writeDebugLog("[Theme] Untouched colours: \(lines.joined(separator: ", "))")
    }
}

// MARK: - Colour bridging

extension IayxifyRGB {
    /// nil for pattern colours, dynamic colours that cannot be resolved, and
    /// anything else that has no straight RGBA answer.
    init?(color: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        self.init(
            red: UInt8(min(max(red * 255, 0), 255).rounded()),
            green: UInt8(min(max(green * 255, 0), 255).rounded()),
            blue: UInt8(min(max(blue * 255, 0), 255).rounded()),
            alpha: UInt8(min(max(alpha * 255, 0), 255).rounded())
        )
    }
}

extension UIColor {
    convenience init(_ rgb: IayxifyRGB) {
        self.init(
            red: CGFloat(rgb.red) / 255,
            green: CGFloat(rgb.green) / 255,
            blue: CGFloat(rgb.blue) / 255,
            alpha: CGFloat(rgb.alpha) / 255
        )
    }
}

/// The ObjC side of the swizzles. Every method here runs with a Spotify object
/// as `self`; calling the same selector again reaches the original
/// implementation because the two methods have been exchanged.
final class IayxifyThemeSwizzles: NSObject {
    @objc dynamic func iayxify_setBackgroundColor(_ color: UIColor?) {
        let engine = IayxifyThemeEngine.shared
        iayxify_setBackgroundColor(engine.themedBackground(for: self, color: color))
    }

    @objc dynamic func iayxify_setTintColor(_ color: UIColor?) {
        let engine = IayxifyThemeEngine.shared
        iayxify_setTintColor(engine.themedTint(for: self, color: color))
    }

    @objc dynamic func iayxify_setTextColor(_ color: UIColor?) {
        let engine = IayxifyThemeEngine.shared
        iayxify_setTextColor(engine.themedText(for: self, color: color))
    }

    @objc dynamic func iayxify_setLayerBackgroundColor(_ color: CGColor?) {
        let engine = IayxifyThemeEngine.shared
        iayxify_setLayerBackgroundColor(engine.themedLayerBackground(for: self, color: color))
    }

    @objc dynamic func iayxify_setOnTintColor(_ color: UIColor?) {
        let engine = IayxifyThemeEngine.shared
        iayxify_setOnTintColor(engine.themedTint(for: self, color: color))
    }

    @objc dynamic func iayxify_setMinimumTrackTintColor(_ color: UIColor?) {
        let engine = IayxifyThemeEngine.shared
        iayxify_setMinimumTrackTintColor(engine.themedTint(for: self, color: color))
    }

    @objc dynamic func iayxify_setProgressTintColor(_ color: UIColor?) {
        let engine = IayxifyThemeEngine.shared
        iayxify_setProgressTintColor(engine.themedTint(for: self, color: color))
    }
}

/// The window-level half of the theme: appearance style, the window's own
/// background, and the list appearance proxies Iayxify's own SwiftUI screens
/// (and, app-wide, Spotify's lists) are built from.
enum IayxifyWindowTheme {
    static func apply(palette: IayxifyPaletteHex, remap: Bool) {
        let themedScreen = IayxifyAppearance.isThemedScreenVisible
        let style: UIUserInterfaceStyle
        if remap || themedScreen {
            style = palette.isDark ? .dark : .light
        } else {
            // Nothing of ours is on screen and Spotify is left alone, so give
            // the window back to Spotify.
            style = .unspecified
        }

        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }

        for window in windows {
            window.overrideUserInterfaceStyle = style
            if remap {
                window.backgroundColor = UIColor(palette.background)
            }
        }

        applyListAppearance(palette: palette, active: remap || themedScreen)
    }

    /// SwiftUI's `List` is a table or collection view depending on the iOS
    /// version, and the cells cover the screen — so all four classes carry the
    /// colours, and none of them keep them once nothing of ours needs them.
    private static func applyListAppearance(palette: IayxifyPaletteHex, active: Bool) {
        let background = active ? UIColor(palette.background) : nil
        let card = active ? UIColor(palette.card) : nil

        UITableView.appearance().backgroundColor = background
        UICollectionView.appearance().backgroundColor = background
        UITableViewCell.appearance().backgroundColor = card
        UICollectionViewCell.appearance().backgroundColor = card
    }
}
