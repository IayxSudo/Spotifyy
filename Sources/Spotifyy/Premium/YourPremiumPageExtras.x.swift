import Orion
import UIKit

/// Additions to Spotify's own "Your Premium" page: the animated rainbow over
/// our name, and an "Iayxify Settings" entry that opens the theme/feature hub.
///
/// Kept in its own hook group because the page class is version specific —
/// `YourPremiumViewController` exists in 9.1.x, and if a future build renames it
/// the group is simply never activated instead of failing at launch.
struct IayxifyPremiumPageGroup: HookGroup { }

class YourPremiumViewControllerExtrasHook: ClassHook<UIViewController> {
    typealias Group = IayxifyPremiumPageGroup
    static let targetName = "YourPremiumViewController"

    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        installSettingsEntry(into: target)
    }

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        installSettingsEntry(into: target)
        IayxifyRainbow.decorate(target.view)
    }

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        // The rainbow mask is sized from the label's bounds, and the entry pill
        // needs re-anchoring when the page resizes, so both are refreshed here.
        installSettingsEntry(into: target)
        IayxifyRainbow.decorate(target.view)
    }
}

func activateIayxifyPremiumPageExtras() {
    guard NSClassFromString("YourPremiumViewController") != nil else {
        writeDebugLog("[INIT] Skipped IayxifyPremiumPageGroup (missing YourPremiumViewController)")
        return
    }

    IayxifyPremiumPageGroup().activate()
    writeDebugLog("[INIT] Activated IayxifyPremiumPageGroup")
}

// MARK: - Entry point

private let iayxifyPremiumEntryTag = 1339
private let iayxifyPremiumEntryHeight: CGFloat = 30

/// Adds the settings entry once: as a nav bar item when the page is pushed (the
/// usual case, it lives under Settings), otherwise as a small pill pinned to the
/// top-right of the sheet. Idempotent — both paths bail out when the tag is
/// already installed, so it is safe to call from every layout pass.
private func installSettingsEntry(into viewController: UIViewController) {
    guard SpotifyyAppearance.options.premiumPageSettingsEntry else { return }

    if let navigationController = viewController.navigationController,
       navigationController.navigationBar.isHidden == false {
        installNavigationItem(into: viewController)
        return
    }

    installFloatingPill(into: viewController)
}

private func installNavigationItem(into viewController: UIViewController) {
    var items = viewController.navigationItem.rightBarButtonItems ?? []
    guard !items.contains(where: { $0.tag == iayxifyPremiumEntryTag }) else { return }

    let item = UIBarButtonItem(
        title: IayxifySettingsLauncher.title,
        style: .plain,
        target: nil,
        action: nil
    )
    item.tag = iayxifyPremiumEntryTag
    item.primaryAction = UIAction { [weak viewController] _ in
        guard let viewController = viewController else { return }
        IayxifySettingsLauncher.open(from: viewController)
    }

    items.insert(item, at: 0)
    viewController.navigationItem.rightBarButtonItems = items

    // Drop any pill a previous layout pass installed before the nav bar showed
    // up, so the entry is never offered twice.
    viewController.view.viewWithTag(iayxifyPremiumEntryTag)?.removeFromSuperview()
}

private func installFloatingPill(into viewController: UIViewController) {
    let host = viewController.view!

    if let existing = host.viewWithTag(iayxifyPremiumEntryTag) {
        position(existing, in: host)
        return
    }

    let pill = UIButton(type: .system)
    pill.tag = iayxifyPremiumEntryTag
    pill.setTitle(IayxifySettingsLauncher.title, for: .normal)
    pill.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    pill.setTitleColor(.white, for: .normal)
    pill.setTitleColor(UIColor(white: 1, alpha: 0.55), for: .highlighted)
    pill.backgroundColor = UIColor(white: 0, alpha: 0.55)
    pill.layer.cornerRadius = iayxifyPremiumEntryHeight / 2
    pill.layer.masksToBounds = true
    pill.sizeToFit()

    pill.addAction(
        UIAction { [weak viewController] _ in
            guard let viewController = viewController else { return }
            IayxifySettingsLauncher.open(from: viewController)
        },
        for: .touchUpInside
    )

    host.addSubview(pill)
    position(pill, in: host)
}

private func position(_ pill: UIView, in host: UIView) {
    let width = max(pill.bounds.width, 44) + 28
    let top = host.safeAreaInsets.top + 10
    pill.frame = CGRect(
        x: host.bounds.width - width - 16,
        y: top,
        width: width,
        height: iayxifyPremiumEntryHeight
    )
    pill.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
}
