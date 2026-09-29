import SwiftUI
import UIKit

/// Animated rainbow for Iayxify's own name on Spotify's native screens.
///
/// Spotify draws the plan name we inject ("Iayxify") itself, and in 9.1 that
/// happens in its Element/SwiftUI layer, so there is often no `UILabel` to
/// mask. Three strategies run in order of how good the result looks:
///
/// 1. A text-only label is masked directly — the sharpest rainbow, because
///    Spotify's own glyphs are what gets the gradient.
/// 2. A label that paints its own pill gets that colour moved to a sibling view
///    behind it first, then is masked — otherwise the mask would recolour the
///    pill and the letters with the same gradient, making the text vanish.
/// 3. No label at all: the badge is found by the colour written into the plan
///    payload and replaced with our own pill drawn the same way, so the rainbow
///    is legible regardless of how Spotify renders its text.
enum IayxifyRainbow {
    /// Text the badge and plan rows are given. Only views matching this are
    /// touched, so the effect can't leak onto Spotify's own copy.
    static let brandName = "Iayxify"

    /// Equal-luminance hues so every letter stays readable while it spins.
    static let colors: [UIColor] = [
        UIColor(red: 1.00, green: 0.27, blue: 0.31, alpha: 1), // red
        UIColor(red: 1.00, green: 0.62, blue: 0.04, alpha: 1), // orange
        UIColor(red: 1.00, green: 0.84, blue: 0.00, alpha: 1), // yellow
        UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1), // green
        UIColor(red: 0.25, green: 0.76, blue: 1.00, alpha: 1), // blue
        UIColor(red: 0.42, green: 0.45, blue: 0.96, alpha: 1), // indigo
        UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1), // violet
    ]

    private static let maskName = "IayxifyRainbowMask"
    private static let spinKey = "IayxifyRainbowSpin"
    /// Background kept behind a pill label we are about to mask.
    private static let backdropTag = 1342
    /// Our own pill, drawn where Spotify's badge was.
    private static let replacementTag = 1343
    private static let spinDuration: CFTimeInterval = 3.0
    /// Keyframes in one full sweep — 24 gives a smooth rotation without a
    /// pointless amount of interpolation work.
    private static let spinSteps = 24

    /// Minimum time between fruitless searches: a layout pass must not turn a
    /// full window walk into a per-frame cost. Anything already decorated is
    /// reused without waiting, so only the "nothing found" case is throttled.
    private static let rescanInterval: CFTimeInterval = 0.5

    /// Last label we decorated. Weak: it belongs to Spotify's view hierarchy.
    private static weak var cachedLabel: UILabel?
    /// Colour that label had before we took it over, so switching the feature
    /// off puts Spotify's own look back.
    private static var cachedLabelColor: UIColor?
    /// Pill colour we moved off a label, for the same reason.
    private static var cachedLabelBackground: UIColor?

    private static weak var cachedPill: UIView?
    private static weak var cachedReplacement: UIView?
    private static var lastScan: CFTimeInterval = 0

    // MARK: - Entry point

    /// Applies the rainbow to the brand name under `root`.
    ///
    /// Safe to call from every layout pass: the tree walk only happens when
    /// nothing decorated is live any more.
    static func decorate(_ root: UIView?) {
        guard let root = root else { return }

        guard SpotifyyAppearance.options.rainbowPremiumName else {
            clear(in: root)
            return
        }

        if let label = cachedLabel,
           text(of: label) == brandName, label.window != nil, label.isDescendant(of: root) {
            // Still on screen and still ours: just re-size the mask. The text
            // check matters because these are recycled cells — a label we
            // colourised can later be handed to a different row.
            apply(to: label)
            return
        }

        if let replacement = cachedReplacement, let pill = cachedPill,
           replacement.window != nil, replacement.isDescendant(of: root),
           replacement.superview === pill.superview {
            replacement.frame = pill.frame
            hide(pill)
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastScan >= rescanInterval else { return }
        lastScan = now

        if decorateLabel(in: root) { return }
        decoratePill(in: root)
    }

    // MARK: - Labels

    private static func decorateLabel(in root: UIView) -> Bool {
        guard let label = brandLabel(in: root) else { return false }

        // A label that paints its own pill keeps its colour on a sibling view,
        // which also becomes the badge's background once the mask is applied.
        if !hasClearBackground(label), let background = label.backgroundColor {
            cachedLabelBackground = background
            moveBackgroundToBackdrop(of: label, colour: background)
        }

        apply(to: label)
        return true
    }

    /// Prefers a text-only label (best result) and falls back to the first label
    /// carrying the name, wherever it is.
    private static func brandLabel(in root: UIView) -> UILabel? {
        var fallback: UILabel?
        var queue: [UIView] = [root]

        while !queue.isEmpty {
            var next: [UIView] = []

            for view in queue where view.tag != replacementTag {
                if let label = view as? UILabel, text(of: label) == brandName {
                    if hasClearBackground(label) { return label }
                    if fallback == nil { fallback = label }
                }
                next.append(contentsOf: view.subviews)
            }

            queue = next
        }

        return fallback
    }

    /// SwiftUI-backed badges set an attributed string and leave `text` nil.
    private static func text(of label: UILabel) -> String? {
        label.text ?? label.attributedText?.string
    }

    private static func hasClearBackground(_ label: UILabel) -> Bool {
        guard let background = label.backgroundColor else { return true }
        return background.cgColor.alpha < 0.02
    }

    private static func moveBackgroundToBackdrop(of label: UILabel, colour: UIColor) {
        guard let superview = label.superview else { return }

        let backdrop: UIView
        if let existing = superview.viewWithTag(backdropTag) {
            backdrop = existing
        } else {
            backdrop = UIView(frame: label.frame)
            backdrop.tag = backdropTag
            backdrop.layer.cornerRadius = label.layer.cornerRadius
            backdrop.layer.cornerCurve = label.layer.cornerCurve
            backdrop.autoresizingMask = label.autoresizingMask
            superview.insertSubview(backdrop, belowSubview: label)
        }

        backdrop.frame = label.frame
        backdrop.backgroundColor = colour

        label.backgroundColor = .clear
    }

    static func apply(to label: UILabel) {
        if cachedLabel !== label {
            cachedLabelColor = label.textColor
        }
        label.textColor = .white
        cachedLabel = label

        if let existing = label.layer.mask as? CAGradientLayer, existing.name == maskName {
            existing.frame = label.bounds
            startSpinIfNeeded(existing)
            return
        }

        let gradient = CAGradientLayer()
        gradient.name = maskName
        gradient.colors = colors.map(\.cgColor)
        // One stop per colour plus the wrap-around stop, so the band is even.
        gradient.locations = (0...colors.count).map { NSNumber(value: Double($0) / Double(colors.count)) }
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.frame = label.bounds

        // A gradient mask shows the label's own pixels tinted by the gradient,
        // which is how a plain `UIColor` text label becomes rainbow text.
        label.layer.mask = gradient
        startSpinIfNeeded(gradient)
    }

    // MARK: - Badges with no label to mask

    private static func decoratePill(in root: UIView) {
        guard let pill = brandPill(in: root), let superview = pill.superview else { return }

        cachedPill = pill
        hide(pill)

        if let replacement = cachedReplacement,
           replacement.superview === superview,
           replacement.isDescendant(of: root) {
            replacement.frame = pill.frame
            return
        }

        removeAll(tag: replacementTag, in: root)

        let replacement = UIView(frame: pill.frame)
        replacement.tag = replacementTag
        replacement.backgroundColor = pill.backgroundColor
            ?? UIColor(Color(hex: SpotifyyAppearance.planAccentHex))
        replacement.layer.cornerRadius = radius(of: pill)
        replacement.layer.cornerCurve = pill.layer.cornerCurve
        replacement.autoresizingMask = pill.autoresizingMask

        let label = UILabel(frame: replacement.bounds)
        label.text = brandName
        label.textAlignment = .center
        label.font = .systemFont(ofSize: max(11, pill.bounds.height * 0.56), weight: .bold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        replacement.addSubview(label)

        superview.insertSubview(replacement, aboveSubview: pill)
        cachedReplacement = replacement

        apply(to: label)
    }

    /// Finds our own badge: a small pill painted in the colour we chose.
    ///
    /// The width-to-height ratio matters — Spotify uses this same pink family
    /// for notification dots, and those are square, so a dot is never mistaken
    /// for the badge and hidden.
    private static func brandPill(in root: UIView) -> UIView? {
        let target = UIColor(Color(hex: SpotifyyAppearance.planAccentHex))
        var found: UIView?

        var queue: [UIView] = [root]
        while !queue.isEmpty, found == nil {
            var next: [UIView] = []

            for view in queue where view.tag != replacementTag && view.tag != backdropTag {
                if isPlanColoured(view, target: target) {
                    found = view
                    break
                }
                next.append(contentsOf: view.subviews)
            }

            queue = next
        }

        return found
    }

    private static func isPlanColoured(_ view: UIView, target: UIColor) -> Bool {
        let bounds = view.bounds
        guard !(view is UIImageView),
              bounds.height >= 16, bounds.height <= 40,
              bounds.width >= 40, bounds.width <= 190,
              bounds.width >= bounds.height * 1.4,
              let background = view.backgroundColor,
              background.cgColor.alpha > 0.9 else {
            return false
        }

        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var vr: CGFloat = 0, vg: CGFloat = 0, vb: CGFloat = 0, va: CGFloat = 0
        guard target.getRed(&tr, green: &tg, blue: &tb, alpha: &ta),
              background.getRed(&vr, green: &vg, blue: &vb, alpha: &va) else {
            return false
        }

        // A loose match on purpose: Spotify may blend the colour with the row it
        // sits in (dark mode, pressed states), and nothing else in the app is
        // this magenta-pink.
        let tolerance: CGFloat = 0.09
        return abs(tr - vr) < tolerance && abs(tg - vg) < tolerance && abs(tb - vb) < tolerance
    }

    private static func radius(of pill: UIView) -> CGFloat {
        guard pill.layer.cornerRadius > 0 else {
            // Spotify's badges are gently rounded rather than capsules.
            return min(pill.bounds.height / 2, 9)
        }
        return pill.layer.cornerRadius
    }

    private static func hide(_ view: UIView) {
        // `alpha` as well as `isHidden`: Spotify re-binds these rows, and a
        // rebuilt pill can have its hidden flag written again.
        view.isHidden = true
        view.alpha = 0
    }

    // MARK: - Teardown

    private static func clear(in root: UIView) {
        if let label = cachedLabel {
            if let mask = label.layer.mask as? CAGradientLayer, mask.name == maskName {
                label.layer.mask = nil
            }
            label.textColor = cachedLabelColor ?? .white
            if let background = cachedLabelBackground {
                label.backgroundColor = background
            }
        }

        cachedLabel = nil
        cachedLabelColor = nil
        cachedLabelBackground = nil

        if let pill = cachedPill {
            pill.isHidden = false
            pill.alpha = 1
        }

        cachedPill = nil
        cachedReplacement = nil

        removeAll(tag: replacementTag, in: root)
        removeAll(tag: backdropTag, in: root)
    }

    private static func removeAll(tag: Int, in root: UIView) {
        while let view = root.viewWithTag(tag) {
            view.removeFromSuperview()
        }
    }

    // MARK: - Animation

    private static func startSpinIfNeeded(_ gradient: CAGradientLayer) {
        guard gradient.animation(forKey: spinKey) == nil else { return }

        // Rotating a linear gradient is done by walking its two end points
        // around the centre of the label: at 180 degrees they have swapped, so
        // the sweep is continuous when the animation repeats.
        var startPoints: [CGPoint] = []
        var endPoints: [CGPoint] = []
        let radius: CGFloat = 0.5

        for step in 0...spinSteps {
            let angle = 2 * Double.pi * Double(step) / Double(spinSteps)
            let dx = CGFloat(cos(angle)) * radius
            let dy = CGFloat(sin(angle)) * radius
            startPoints.append(CGPoint(x: 0.5 - dx, y: 0.5 - dy))
            endPoints.append(CGPoint(x: 0.5 + dx, y: 0.5 + dy))
        }

        let start = CAKeyframeAnimation(keyPath: "startPoint")
        start.values = startPoints
        start.duration = spinDuration
        start.repeatCount = .infinity
        start.calculationMode = .linear

        let end = CAKeyframeAnimation(keyPath: "endPoint")
        end.values = endPoints
        end.duration = spinDuration
        end.repeatCount = .infinity
        end.calculationMode = .linear

        gradient.add(start, forKey: spinKey + ".start")
        gradient.add(end, forKey: spinKey + ".end")
    }
}
