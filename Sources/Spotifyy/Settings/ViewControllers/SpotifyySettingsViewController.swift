import SwiftUI
import UIKit 

class SpotifyySettingsViewController: SPTPageViewController {
    let settingsView: AnyView
    private var hasShownSpecialLicense = false
    
    init(_ frame: CGRect, settingsView: AnyView, navigationTitle: String) {
        self.settingsView = settingsView
        super.init(nibName: nil, bundle: nil)
        
        title = navigationTitle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Themes Iayxify's own screens. Entering here (rather than in
        // viewDidLoad) makes sure the appearance proxies are set before the
        // incoming screen's views are built, and the counter in
        // SpotifyyAppearance keeps a pushed sub-screen from resetting the
        // theme its parent is still using.
        SpotifyyAppearance.enterThemedScreen()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        SpotifyyAppearance.leaveThemedScreen()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let theme = SpotifyyAppearance.palette
        let hostingController = UIHostingController(rootView: settingsView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        // Shows the theme behind the SwiftUI list for the transparent parts.
        view.backgroundColor = UIColor(theme.background)
        view.overrideUserInterfaceStyle = theme.style
        
        view.addSubview(hostingController.view)
        addChild(hostingController)
        hostingController.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Become first responder so we can receive motion events
        becomeFirstResponder()
    }
    
    override var canBecomeFirstResponder: Bool { true }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake, !hasShownSpecialLicense else { return }
        hasShownSpecialLicense = true
        
        let alert = UIAlertController(
            title: "Special License Detected",
            message: "Subscribed to Elsa by Hysan since 2026.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Prayers for Hysan 🙏", style: .default))
        WindowHelper.shared.present(alert)
    }
    
    @objc func openRepositoryUrl(_ sender: UIButton) {
        UIApplication.shared.open(URL(string: "https://github.com/jaydenjcpy/SpotifyyReincarnated")!)
    }
}
