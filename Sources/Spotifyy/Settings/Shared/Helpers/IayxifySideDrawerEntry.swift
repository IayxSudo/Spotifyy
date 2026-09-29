import UIKit

/// The "Iayxify Settings" row inside Spotify's side drawer — the panel with
/// Add account / Your Premium / What's new / Settings and privacy.
///
/// Spotify builds that panel from its own item plugins (`SideDrawerItem`), and a
/// tweak can't hand it an extra item without the app's private Swift types, so
/// the row is placed into the drawer's own list instead.
///
/// Two things matter for it to look native:
///
/// - **Geometry.** Spotify's rows are not UIKit cells you can clone in 9.1 — the
///   content is rendered by its Element layer — so the metrics below were
///   measured from the drawer itself (icon 24pt at x=16, title at x=52, 52pt
///   rows, white on the drawer's background) rather than copied from a row.
/// - **Placement.** The tallest gap between Spotify's rows wins, and if no gap
///   is tall enough the row goes below the last one. Nothing Spotify laid out is
///   ever moved, so rows can't end up overlapping.
enum IayxifySideDrawerEntry {
    /// Distinct from the other entry points (1337-1339) so no two can stack up.
    private static let tag = 1340
    private static let defaultHeight: CGFloat = 52
    private static let minimumHeight: CGFloat = 44
    private static let maximumHeight: CGFloat = 72
    private static let iconLeading: CGFloat = 16
    private static let iconSide: CGFloat = 24
    private static let titleGap: CGFloat = 12
    private static let titleSize: CGFloat = 17

    /// Called from the drawer's layout passes. Idempotent: it repositions the
    /// row it owns rather than adding another.
    static func install(in viewController: UIViewController) {
        guard let host = viewController.view else { return }

        guard SpotifyyAppearance.options.showSideDrawerEntry else {
            removeEntry(in: host)
            return
        }

        guard let scrollView = drawerScrollView(in: host) else {
            installBottomRow(in: host)
            return
        }

        let rows = rowFrames(in: scrollView)
        guard let last = rows.last else {
            installBottomRow(in: host)
            return
        }

        let height = clamp(last.height)
        let y = placement(rows: rows, height: height)

        let row = existingRow(in: host) ?? makeRow()
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

    /// Picks where the row goes. Returns a y in the scroll view's coordinates.
    private static func placement(rows: [CGRect], height: CGFloat) -> CGFloat {
        var bestGap: CGFloat = 0
        var bestY: CGFloat = 0

        for (current, next) in zip(rows, rows.dropFirst()) {
            let gap = next.minY - current.maxY
            guard gap >= height + 8, gap > bestGap else { continue }
            bestGap = gap
            // Centred in the gap, which keeps Spotify's own spacing symmetric.
            bestY = current.maxY + (gap - height) / 2
        }

        if bestGap > 0 { return bestY }

        // No room between rows: sit under the last one, keeping the spacing the
        // drawer uses elsewhere.
        return rows[rows.count - 1].maxY + 12
    }

    /// Spotify's own rows, in the scroll view's coordinates.
    ///
    /// A collection view is asked for its visible cells — that is exact and
    /// doesn't care how the row content is drawn. Anything else falls back to
    /// geometry: full-width strips of row height, without descending into a
    /// row's own subviews so nothing is counted twice.
    private static func rowFrames(in scrollView: UIScrollView) -> [CGRect] {
        if let collectionView = scrollView as? UICollectionView {
            let cells = collectionView.visibleCells
                .map { $0.convert($0.bounds, to: collectionView) }
                .filter { $0.height >= 36 && $0.height <= 130 }
            if !cells.isEmpty {
                return cells.sorted { $0.minY < $1.minY }
            }
        }

        var found: [CGRect] = []

        func walk(_ view: UIView, depth: Int) {
            for subview in view.subviews {
                guard subview.tag != tag else { continue }

                let frame = subview.convert(subview.bounds, to: scrollView)
                guard frame.height >= 36, frame.height <= 130,
                      frame.width >= scrollView.bounds.width * 0.5 else {
                    if depth < 3 { walk(subview, depth: depth + 1) }
                    continue
                }

                found.append(frame)
            }
        }

        walk(scrollView, depth: 0)
        return found.sorted { $0.minY < $1.minY }
    }

    private static func clamp(_ height: CGFloat) -> CGFloat {
        guard height.isFinite, height > 0 else { return defaultHeight }
        return min(max(height, minimumHeight), maximumHeight)
    }

    /// The drawer's own scroll view: matched by class name first, because by the
    /// time its layout runs the drawer is not the only scroll view around.
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

    private static func makeRow() -> UIView {
        let row = IayxifySideDrawerRowButton(
            font: .systemFont(ofSize: titleSize),
            textColor: .white,
            iconLeading: iconLeading,
            iconSide: iconSide,
            titleGap: titleGap
        )
        row.addAction(UIAction { _ in IayxifySettingsLauncher.openOverTopmost() }, for: .touchUpInside)
        return row
    }

    /// Last resort when the drawer's list can't be found: the same row, pinned
    /// into the empty space at the bottom of the panel, so the entry is never
    /// simply missing.
    private static func installBottomRow(in host: UIView) {
        let row = existingRow(in: host) ?? makeRow()
        if row.superview !== host {
            host.addSubview(row)
        }

        row.frame = CGRect(
            x: 0,
            y: host.bounds.maxY - host.safeAreaInsets.bottom - defaultHeight - 12,
            width: host.bounds.width,
            height: defaultHeight
        )
        row.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
    }
}

/// A drawer row: icon, title, and Spotify-like tap feedback, drawn to match the
/// rows it sits between.
private final class IayxifySideDrawerRowButton: UIButton {
    init(font: UIFont, textColor: UIColor, iconLeading: CGFloat, iconSide: CGFloat, titleGap: CGFloat) {
        super.init(frame: .zero)

        let iconView = UIImageView()
        iconView.image = UIImage(systemName: "paintbrush.pointed.fill")
            ?? UIImage(systemName: "gearshape.fill")
        // Tinted like the title, not with the theme accent: Spotify's drawer is
        // monochrome, and a coloured icon is what makes an added row stand out.
        iconView.tintColor = textColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // Deliberately not the button's own `titleLabel`: the layout is done with
        // our own label so it matches Spotify's row metrics exactly.
        let nameLabel = UILabel()
        nameLabel.text = IayxifySettingsLauncher.title
        nameLabel.font = font
        nameLabel.textColor = textColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: iconLeading),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSide),
            iconView.heightAnchor.constraint(equalToConstant: iconSide),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: titleGap),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -iconLeading),
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
