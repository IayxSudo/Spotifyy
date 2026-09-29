import SwiftUI
import UIKit

/// One place that opens Iayxify's settings from any screen, so the entry points
/// added to Spotify's own pages don't each have to reimplement the navigation
/// controller + GitHub button wiring.
enum IayxifySettingsLauncher {
    /// Title used on every entry point (nav bar row, sidebar row, premium page
    /// button) and on the settings screen itself.
    static let title = "Iayxify Settings"

    /// Pushes onto an existing navigation stack when there is one, and presents
    /// a wrapped navigation controller otherwise. Spotify's "Your Premium" page
    /// is usually pushed under Settings, but can also appear as its own sheet.
    static func open(from viewController: UIViewController) {
        if let navigationController = viewController.navigationController {
            push(on: navigationController, hostBounds: viewController.view.bounds)
            return
        }

        let navigationController = UINavigationController()
        let host = makeHost(
            bounds: viewController.view.bounds,
            navigationController: navigationController
        )
        navigationController.viewControllers = [host]
        navigationController.modalPresentationStyle = .pageSheet
        viewController.present(navigationController, animated: true)
    }

    /// Presents the settings over whatever is on screen right now.
    ///
    /// For entry points that live inside Spotify's own panels — the side drawer
    /// above all. Pushing is not safe there, because the panel's navigation
    /// controller is often not the visible one, and UIKit quietly does nothing
    /// when a presenter is mid-transition. Always finding the topmost controller
    /// and always presenting is the version that can't end in a dead tap.
    static func openOverTopmost() {
        guard let topmost = topmostViewController() else { return }

        let navigationController = UINavigationController()
        let host = makeHost(
            bounds: topmost.view.bounds,
            navigationController: navigationController
        )
        navigationController.viewControllers = [host]
        navigationController.modalPresentationStyle = .pageSheet
        topmost.present(navigationController, animated: true)
    }

    /// Topmost controller of the key window, following the presentation chain
    /// (so a tap inside a presented panel presents on top of that panel).
    private static func topmostViewController() -> UIViewController? {
        let sceneWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }

        let window = sceneWindows.first { $0.isKeyWindow } ?? sceneWindows.first

        var viewController = window?.rootViewController
        while let presented = viewController?.presentedViewController {
            viewController = presented
        }

        return viewController
    }

    static func push(on navigationController: UINavigationController, hostBounds: CGRect) {
        let host = makeHost(bounds: hostBounds, navigationController: navigationController)
        navigationController.pushViewController(host, animated: true)
    }

    private static func makeHost(
        bounds: CGRect,
        navigationController: UINavigationController
    ) -> SpotifyySettingsViewController {
        let host = SpotifyySettingsViewController(
            bounds,
            settingsView: AnyView(SpotifyySettingsView(navigationController: navigationController)),
            navigationTitle: title
        )

        if let githubImage = BundleHelper.shared.uiImage("github"), githubImage.size != .zero {
            let button = UIButton(type: .system)
            button.setImage(githubImage.withRenderingMode(.alwaysOriginal), for: .normal)
            button.addTarget(
                host,
                action: #selector(host.openRepositoryUrl(_:)),
                for: .touchUpInside
            )

            let item = UIBarButtonItem(customView: button)
            item.customView?.heightAnchor.constraint(equalToConstant: 22).isActive = true
            item.customView?.widthAnchor.constraint(equalToConstant: 22).isActive = true
            host.navigationItem.rightBarButtonItem = item
        }

        return host
    }
}
