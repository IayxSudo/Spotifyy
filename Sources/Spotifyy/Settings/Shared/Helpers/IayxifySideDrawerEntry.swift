import SwiftUI
import UIKit

/// The "Iayxify Settings" row inside Spotify's side drawer — the panel with
/// Add account / Your Premium / What's new / Settings and privacy.
///
/// Spotify builds that panel from its own item plugins (`SideDrawerItem`), and a
/// tweak can't hand it an extra item without the app's private Swift types, so
/// the row is placed into the drawer's scroll view instead.
///
/// Placement is deliberately un-clever: the tallest gap between Spotify's own
/// rows wins, and if no gap is tall enough the row goes below the last one.
/// Nothing Spotify laid out is ever moved, so the drawer can't end up with rows
/// stacked on top of each other — worst case the row sits lower than the user
/// might have picked.
enum IayxifySideDrawerEntry {
    /// Distinct from the other entry points (1337-1339) so no two can stack up.
    private static let tag = 1340
    private static let defaultHeight: CGFloat = 52
    private static let minimumHeight: CGFloat = 44
    private static let maximumHeight: CGFloat = 72

    /// Called from the drawer's layout passes. Idempotent: it repositions the
    /// row it owns rather than adding another.
    static func install(in viewController: UIViewController) {
        guard let host = viewController.view else { return }

        guard SpotifyyAppearance.options.showSideDrawerEntry else {
            removeEntry(in: host)
            return
        }

        guard let scrollView = drawerScrollView(in: host) else {
            installFooterPill(in: host)
            return
        }

        let rows = rowCandidates(in: scrollView)
        guard let reference = rows.last else {
            installFooterPill(in: host)
            return
        }

        let height = clamp(reference.frame.height)
        let y = placement(rows: rows, height: height)

        let row = existingRow(in: host) ?? makeRow(font: reference.font, color: reference.color)
        if row.superview !== scrollView {
            scrollView.addSubview(row)
        }

        row.frame = CGRect(x: 0, y: y, width: scrollView.bounds.width, height: height)
        row.autoresizingMask = [.flexibleWidth]

        // Only ever grow the content: the row normally fits in the space the
        // drawer already has, and shrinking would clip Spotify's own rows.
        let needed = row.frame.maxY + 16
        if scrollView.contentSize.height < needed {
            scrollView.contentSize.height = needed
        }
    }

    // MARK: - Placement

    private struct Candidate {
        let view: UIView
        let frame: CGRect
        /// Typography taken from a real drawer row, so ours matches exactly
        /// instead of guessing at Spotify's font.
        let font: UIFont
        let color: UIColor
    }

    /// Picks where the row goes. Returns a y in the scroll view's coordinates.
    private static func placement(rows: [Candidate], height: CGFloat) -> CGFloat {
        var bestGap: CGFloat = 0
        var bestY: CGFloat = 0

        for (current, next) in zip(rows, rows.dropFirst()) {
            let gap = next.frame.minY - current.frame.maxY
            guard gap >= height + 8, gap > bestGap else { continue }
            bestGap = gap
            // Centred in the gap, which keeps Spotify's own spacing symmetric.
            bestY = current.frame.maxY + (gap - height) / 2
        }

        if bestGap > 0 { return bestY }

        // No room between rows: sit under the last one, keeping the spacing the
        // drawer uses elsewhere.
        let last = rows[rows.count - 1]
        return last.frame.maxY + 12
    }

    /// Row-like views: roughly a real row's height, wide, and containing text.
    /// The walk stops at the first match on each branch, so a row is never
    /// counted twice through its own subviews.
    private static func rowCandidates(in scrollView: UIScrollView) -> [Candidate] {
        var found: [Candidate] = []

        func walk(_ view: UIView, depth: Int) {
            for subview in view.subviews {
                guard subview.tag != tag else { continue }

                let frame = subview.convert(subview.bounds, to: scrollView)

                if frame.height >= 36, frame.height <= 130, frame.width >= 140,
                   let text = firstText(in: subview) {
                    found.append(
                        Candidate(
                            view: subview,
                            frame: frame,
                            font: text.font ?? .systemFont(ofSize: 16),
                            color: text.textColor ?? .white
                        )
                    )
                    continue
                }

                if depth < 4 { walk(subview, depth: depth + 1) }
            }
        }

        walk(scrollView, depth: 0)
        return found.sorted { $0.frame.minY < $1.frame.minY }
    }

    private static func firstText(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, let text = label.text, !text.isEmpty {
            return label
        }
        for subview in view.subviews {
            if let label = firstText(in: subview) { return label }
        }
        return nil
    }

    private static func clamp(_ height: CGFloat) -> CGFloat {
        guard height.isFinite, height > 0 else { return defaultHeight }
        return min(max(height, minimumHeight), maximumHeight)
    }

    /// The drawer's own scroll view. Matched by class name first, because by the
    /// time its layout runs the drawer is not the only scroll view in the
    /// hierarchy.
    private static func drawerScrollView(in host: UIView) -> UIScrollView? {
        var candidates: [UIScrollView] = []

        func walk(_ view: UIView, depth: Int) {
            for subview in view.subviews {
                if let scrollView = subview as? UIScrollView {
                    candidates.append(scrollView)
                }
                if depth < 4 { walk(subview, depth: depth + 1) }
            }
        }

        walk(host, depth: 0)

        let named = candidates.first {
            NSStringFromClass(type(of: $0)).contains("SideDrawer")
        }

        // Fall back to the widest one: the drawer's list spans the whole panel.
        return named ?? candidates.max { $0.bounds.width < $1.bounds.width }
    }

    // MARK: - The row

    private static func existingRow(in host: UIView) -> UIView? {
        host.viewWithTag(tag)
    }

    private static func removeEntry(in host: UIView) {
        while let tagged = host.viewWithTag(tag) {
            tagged.removeFromSuperview()
        }
    }

    private static func makeRow(font: UIFont, color: UIColor) -> UIView {
        let row = IayxifySideDrawerRowButton(
            font: font,
            textColor: color,
            tint: UIColor(SpotifyyAppearance.accentColor)
        )
        row.addAction(UIAction { _ in open() }, for: .touchUpInside)
        return row
    }

    /// The drawer is a modal panel over the app, so it has to be closed before
    /// the settings screen is presented — otherwise the sheet appears stacked on
    /// a panel that stays open behind it.
    private static func open() {
        guard let drawer = currentDrawer() else {
            IayxifySettingsLauncher.open(from: WindowHelper.shared.rootViewController)
            return
        }

        guard let presenter = drawer.presentingViewController else {
            IayxifySettingsLauncher.open(from: drawer)
            return
        }

        drawer.dismiss(animated: true) {
            IayxifySettingsLauncher.open(from: presenter)
        }
    }

    /// The drawer on screen, found through the presentation chain rather than a
    /// stored reference that could go stale.
    private static func currentDrawer() -> UIViewController? {
        var candidate = WindowHelper.shared.rootViewController.presentedViewController
        while let viewController = candidate {
            if NSStringFromClass(type(of: viewController)).contains("SideDrawer") {
                return viewController
            }
            candidate = viewController.presentedViewController
        }
        return nil
    }

    /// Last resort when the drawer's list can't be found: a branded capsule in
    /// the drawer's footer, so the entry is never simply missing.
    private static func installFooterPill(in host: UIView) {
        let height: CGFloat = 44

        let pill: UIButton
        if let existing = host.viewWithTag(tag) as? UIButton {
            pill = existing
        } else {
            pill = UIButton(type: .custom)
            pill.tag = tag
            pill.setTitle(IayxifySettingsLauncher.title, for: .normal)
            pill.setTitleColor(.white, for: .normal)
            pill.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            pill.backgroundColor = UIColor(SpotifyyAppearance.accentColor)
            pill.layer.cornerRadius = height / 2
            pill.layer.masksToBounds = true
            pill.addAction(UIAction { _ in self.open() }, for: .touchUpInside)
            host.addSubview(pill)
        }

        pill.frame = CGRect(
            x: 20,
            y: host.bounds.maxY - host.safeAreaInsets.bottom - height - 24,
            width: 190,
            height: height
        )
        pill.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin]
    }
}

/// A drawer row. Subclasses `UIButton` so it gets Spotify-like tap feedback
/// without reproducing their highlight view.
private final class IayxifySideDrawerRowButton: UIButton {
    /// Matches the inset and spacing Spotify's own drawer rows use, measured
    /// from the rows this row is placed between.
    private static let leadingInset: CGFloat = 24
    private static let iconSide: CGFloat = 24
    private static let iconGap: CGFloat = 20

    private let iconView = UIImageView()
    private let nameLabel = UILabel()

    init(font: UIFont, textColor: UIColor, tint: UIColor) {
        super.init(frame: .zero)

        iconView.image = UIImage(systemName: "paintbrush.pointed.fill")
            ?? UIImage(systemName: "gearshape.fill")
        iconView.tintColor = tint
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.text = IayxifySettingsLauncher.title
        nameLabel.font = font
        nameLabel.textColor = textColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingInset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSide),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSide),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Self.iconGap),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.leadingInset),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? UIColor(white: 1, alpha: 0.07) : .clear
        }
    }
}
