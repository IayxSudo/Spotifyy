import Orion
import UIKit

/// Spotify calls this panel the *side drawer* (`SideDrawer_PlatformImpl`), and
/// it is where "Your Premium" actually shows the Iayxify badge — the pill the
/// user sees when they tap their avatar. The rainbow was previously only applied
/// inside `YourPremiumViewController`, which is the *page* behind that row, so
/// nothing ever touched the badge people look at.
///
/// The class is Swift, so it is hooked by mangled name, and the group is only
/// activated when it exists: a rename in a future Spotify build costs the entry
/// point, not the launch.
struct IayxifySideDrawerGroup: HookGroup { }

class SideDrawerViewControllerExtrasHook: ClassHook<UIViewController> {
    typealias Group = IayxifySideDrawerGroup
    static let targetName = "_TtC23SideDrawer_PlatformImpl24SideDrawerViewController"

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        refresh()
    }

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        refresh()
    }

    /// Everything here is idempotent and self-throttling, so it is safe to run
    /// from every layout pass.
    private func refresh() {
        IayxifySideDrawerEntry.install(in: target)
        IayxifyRainbow.decorate(target.view)
        // The badge is drawn by an Element row component rather than by a label
        // we can hook, so if the walk above found nothing the pill is repainted.
        IayxifyRainbow.decorateBadge(in: target.view)

        // Last resort for a badge hosted outside the drawer's own view: look at
        // the whole window before giving up.
        if let window = target.view.window {
            IayxifyRainbow.decorate(window)
        }
    }
}

func activateIayxifySideDrawerExtras() {
    let drawerClass = "_TtC23SideDrawer_PlatformImpl24SideDrawerViewController"

    // Both halves matter: the class has to exist *and* be a view controller, or
    // hooking it with `ClassHook<UIViewController>` would be wrong.
    guard NSClassFromString(drawerClass) is UIViewController.Type else {
        writeDebugLog("[INIT] Skipped IayxifySideDrawerGroup (no UIViewController \(drawerClass))")
        return
    }

    IayxifySideDrawerGroup().activate()
    writeDebugLog("[INIT] Activated IayxifySideDrawerGroup")
}
