import Orion
import UIKit

/// Spotify calls this panel the *side drawer* (`SideDrawer_PlatformImpl`), and
/// it is where "Your Premium" actually shows the Iayxify badge — the pill the
/// user sees when they tap their avatar. The rainbow was originally only applied
/// inside `YourPremiumViewController`, which is the *page* behind that row, so
/// nothing ever touched the badge people look at.
///
/// The class is Swift, so it is hooked by mangled name, and the group is only
/// activated when it exists *and* is a view controller: a rename in a future
/// Spotify build costs the entry point, not the launch.
struct IayxifySideDrawerGroup: HookGroup { }

class SideDrawerViewControllerExtrasHook: ClassHook<UIViewController> {
    typealias Group = IayxifySideDrawerGroup
    static let targetName = "_TtC23SideDrawer_PlatformImpl24SideDrawerViewController"

    func viewDidAppear(_ animated: Bool) {
        orig.viewDidAppear(animated)
        refreshIayxifySideDrawer(target)

        // The drawer builds its badge and rows a beat after it appears, and a
        // Swift class may not implement `viewDidLayoutSubviews` at all — so a few
        // retries are what actually catches them.
        // The controller is captured directly rather than through `self`, so the
        // retries don't depend on how long the hook instance is kept alive.
        let drawer = target
        for delay in [0.15, 0.5, 1.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                refreshIayxifySideDrawer(drawer)
            }
        }
    }

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        refreshIayxifySideDrawer(target)
    }
}

/// Everything here is idempotent and self-throttling, so it is safe to run from
/// every layout pass. File scope on purpose: anything declared inside the hook
/// class would be swizzled onto Spotify's controller by Orion.
func refreshIayxifySideDrawer(_ viewController: UIViewController) {
    IayxifySideDrawerEntry.install(in: viewController)
    IayxifyRainbow.decorate(viewController.view)

    // Last resort for a badge hosted outside the drawer's own view: look at the
    // whole window before giving up.
    if let window = viewController.view.window, window !== viewController.view {
        IayxifyRainbow.decorate(window)
    }
}

func activateIayxifySideDrawerExtras() {
    let drawerClass = "_TtC23SideDrawer_PlatformImpl24SideDrawerViewController"

    guard NSClassFromString(drawerClass) is UIViewController.Type else {
        writeDebugLog("[INIT] Skipped IayxifySideDrawerGroup (no UIViewController \(drawerClass))")
        return
    }

    IayxifySideDrawerGroup().activate()
    writeDebugLog("[INIT] Activated IayxifySideDrawerGroup")
}
