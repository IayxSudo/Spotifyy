import Orion
import UIKit

/// Repaints each screen as it comes up.
///
/// The engine's swizzles already catch colours set *after* installation, but a
/// view can be handed its colour first and shown later (recycled cells,
/// prebuilt panels), so every appearance is also a chance to reconcile the
/// subtree. The reconcile is stamped per theme, so a screen is walked once per
/// theme rather than on every appearance.
struct IayxifyThemeRefreshGroup: HookGroup { }

class IayxifyThemeRefreshHook: ClassHook<UIViewController> {
    typealias Group = IayxifyThemeRefreshGroup

    func viewWillAppear(_ animated: Bool) {
        orig.viewWillAppear(animated)
        IayxifyThemeEngine.shared.repaint(target.view)
    }

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        IayxifyThemeEngine.shared.repaint(target.view)
    }
}

func activateIayxifyThemeRefresh() {
    guard IayxifyThemeEngine.shared.isInstalled else {
        writeDebugLog("[INIT] Skipped IayxifyThemeRefreshGroup (engine not installed)")
        return
    }

    IayxifyThemeRefreshGroup().activate()
    writeDebugLog("[INIT] Activated IayxifyThemeRefreshGroup")
}
