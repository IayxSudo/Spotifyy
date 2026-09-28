import UIKit

/// Animated rainbow for Iayxify's own name on Spotify's native screens.
///
/// Spotify draws the plan name we inject ("Iayxify") itself, so the only handle
/// we get is the rendered view. This walks a view tree for labels whose text is
/// exactly the brand name and masks them with a gradient that rotates around
/// the label, which is what makes the colour appear to spin.
///
/// If Spotify renders that name as SwiftUI text there is no `UILabel` to mask
/// and `decorate` simply finds nothing — the plan payload's fallback colour is
/// used instead.
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

    /// Last label we decorated, so the layout pass doesn't re-walk the view tree
    /// on every frame. Weak: the label belongs to Spotify's view hierarchy.
    private static weak var cachedLabel: UILabel?

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

        if let cached = cachedLabel, cached.window != nil, cached.isDescendant(of: root) {
            // Still on screen and still inside this page: just re-size the mask.
            apply(to: cached)
            return
        }

        guard let label = firstBrandLabel(in: root) else { return }
        apply(to: label)
    }

    /// Walks the tree breadth-first — the name is usually near the top of these
    /// pages, so this avoids descending into the whole list.
    private static func firstBrandLabel(in root: UIView) -> UILabel? {
        var queue: [UIView] = [root]

        while !queue.isEmpty {
            var next: [UIView] = []

            for view in queue {
                if let label = view as? UILabel, label.text == brandName {
                    return label
                }
                next.append(contentsOf: view.subviews)
            }

            queue = next
        }

        return nil
    }

    static func apply(to label: UILabel) {
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
    ///
    /// Only needed when the feature is switched off while the label is on
    /// screen: the gradient mask is what gives the text its colour, so the
    /// label is left with the opaque colour `apply` set until Spotify rebuilds
    /// it. Purely cosmetic and rare.
    static func clear(_ label: UILabel) {
        guard let mask = label.layer.mask as? CAGradientLayer, mask.name == maskName else { return }
        label.layer.mask = nil
    }

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
