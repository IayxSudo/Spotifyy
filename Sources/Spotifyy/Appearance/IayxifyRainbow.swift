import SwiftUI
import UIKit

/// Animated rainbow for Iayxify's own name on Spotify's native screens.
///
/// Spotify draws the plan name we inject ("Iayxify") itself, so the only handle
/// we get is the rendered view. Two paths exist:
///
/// - `decorate(_:)` walks a view tree for text labels whose text is exactly the
///   brand name and masks them with a gradient that rotates around the label,
///   which is what makes the colour appear to spin.
/// - `decorateBadge(in:)` covers the case where there is no label at all: some
///   of Spotify's badges draw their text with an Element component. Those are
///   found by the colour we put in the badge payload — the one signal that is
///   ours and stable — and repainted with a masked label on top.
enum IayxifyRainbow {
    /// Text the badge and plan rows are given. Only labels matching this are
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
    private static let spinDuration: CFTimeInterval = 3.0
    /// Keyframes in one full sweep — 24 gives a smooth rotation without a
    /// pointless amount of interpolation work.
    private static let spinSteps = 24

    /// Tag on the repaint view `decorateBadge(in:)` adds. Prefixed so it can't
    /// collide with the entry points' 1337-1340 range.
    private static let overlayTag = 1341

    /// Minimum time between fruitless searches: a layout pass must not turn a
    /// full window walk into a per-frame cost. A live label or badge is reused
    /// without waiting, so only the "nothing to decorate" case is throttled.
    private static let rescanInterval: CFTimeInterval = 0.5

    /// Last label we decorated, so the layout pass doesn't re-walk the view tree
    /// on every frame. Weak: the label belongs to Spotify's view hierarchy.
    private static weak var cachedLabel: UILabel?
    /// Colour the label had before we took it over, so switching the feature off
    /// puts Spotify's own colour back instead of leaving white text behind.
    private static var cachedLabelColor: UIColor?

    /// Last badge we repainted, so a live one isn't searched for again.
    private static weak var cachedPill: UIView?
    private static var lastBadgeScan: CFTimeInterval = 0
    private static var lastLabelScan: CFTimeInterval = 0

    // MARK: - Text labels

    /// Applies the animated rainbow to the brand name under `root`.
    ///
    /// Safe to call from every layout pass: the tree walk only happens when
    /// there is no live decorated label yet.
    static func decorate(_ root: UIView?) {
        guard let root = root else { return }

        guard SpotifyyAppearance.options.rainbowPremiumName else {
            // Turning the option off should also undo an already-rainbow label.
            if let cached = cachedLabel { clear(cached) }
            cachedLabel = nil
            return
        }

        if let cached = cachedLabel, isUsable(cached, in: root) {
            // Still on screen, still inside this root and still showing our
            // name: just re-size the mask. The text check matters because these
            // are recycled cells — a label we colourised can later be handed to
            // a different row.
            apply(to: cached)
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastLabelScan >= rescanInterval else { return }
        lastLabelScan = now

        guard let label = firstBrandLabel(in: root) else { return }
        apply(to: label)
    }

    private static func isUsable(_ label: UILabel, in root: UIView) -> Bool {
        label.text == brandName && label.window != nil && label.isDescendant(of: root)
    }

    /// Walks the tree breadth-first — the name is usually near the top of these
    /// pages, so this avoids descending into the whole list.
    private static func firstBrandLabel(in root: UIView) -> UILabel? {
        var queue: [UIView] = [root]

        while !queue.isEmpty {
            var next: [UIView] = []

            for view in queue {
                if let label = view as? UILabel, label.text == brandName, hasClearBackground(label) {
                    return label
                }
                next.append(contentsOf: view.subviews)
            }

            queue = next
        }

        return nil
    }

    /// Only text-only labels can be masked: the mask replaces every pixel the
    /// layer draws, so a label that paints its own pill background would turn
    /// into a solid rainbow bar with the letters swallowed by it. Those are
    /// handled by `decorateBadge(in:)` instead.
    private static func hasClearBackground(_ label: UILabel) -> Bool {
        guard let background = label.backgroundColor else { return true }
        return background.cgColor.alpha < 0.02
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

    /// Removes the mask so a recycled label goes back to normal text.
    static func clear(_ label: UILabel) {
        if let mask = label.layer.mask as? CAGradientLayer, mask.name == maskName {
            label.layer.mask = nil
        }
        label.textColor = cachedLabelColor ?? .white
        cachedLabelColor = nil
    }

    // MARK: - Badges that aren't labels

    /// Repaints a badge whose text Spotify draws without a label.
    ///
    /// The badge is identified by the colour written into the plan payload
    /// (`SpotifyyAppearance.planAccentHex`) — deliberately a colour Spotify
    /// itself never uses for these pills, so finding it means the pill is ours.
    static func decorateBadge(in root: UIView?) {
        guard let root = root else { return }

        guard SpotifyyAppearance.options.rainbowPremiumName else {
            cachedPill?.viewWithTag(overlayTag)?.removeFromSuperview()
            cachedPill = nil
            return
        }

        if let cached = cachedPill, cached.window != nil, cached.isDescendant(of: root) {
            return
        }
        cachedPill = nil

        // Nothing to do when a real label carries the name: masking that is
        // better than covering Spotify's text with our own.
        if firstBrandLabel(in: root) != nil { return }

        guard let pill = brandBadge(in: root) else { return }
        cachedPill = pill
        guard pill.viewWithTag(overlayTag) == nil else { return }

        let cover = UIView(frame: pill.bounds)
        cover.tag = overlayTag
        cover.backgroundColor = pill.backgroundColor
        cover.layer.cornerRadius = pill.layer.cornerRadius
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let label = UILabel(frame: cover.bounds)
        label.text = brandName
        label.textAlignment = .center
        label.font = .systemFont(ofSize: max(11, pill.bounds.height * 0.58), weight: .bold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.addSubview(label)

        pill.addSubview(cover)
        apply(to: label)
    }

    /// Finds our own badge pill: small, rounded, and painted in the plan colour
    /// we chose. Throttled, because a miss means walking the whole window.
    private static func brandBadge(in root: UIView) -> UIView? {
        let now = CACurrentMediaTime()
        guard now - lastBadgeScan >= rescanInterval else { return nil }
        lastBadgeScan = now

        let target = UIColor(Color(hex: SpotifyyAppearance.planAccentHex))
        var found: UIView?

        var queue: [UIView] = [root]
        while !queue.isEmpty, found == nil {
            var next: [UIView] = []

            for view in queue where view.tag != overlayTag {
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
        guard bounds.height >= 16, bounds.height <= 36,
              bounds.width >= 26, bounds.width <= 180,
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
