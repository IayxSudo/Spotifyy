import SwiftUI
import UIKit

/// One place that opens Iayxify's settings from any screen, so the entry point
/// added to Spotify's own pages doesn't have to reimplement the navigation
/// controller + GitHub button wiring.
enum IayxifySettingsLauncher {
    /// Title used on every entry point (nav bar row, premium page button) and
    /// on the settings screen itself.
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
