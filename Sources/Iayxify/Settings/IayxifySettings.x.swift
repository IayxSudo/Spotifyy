import Orion
import SwiftUI
import UIKit

// Settings integration - only works on non-9.1.x versions
struct SettingsIntegrationGroup: HookGroup { }

class ProfileSettingsSectionHook: ClassHook<NSObject> {
    typealias Group = SettingsIntegrationGroup
    static let targetName = "ProfileSettingsSection"

    func numberOfRows() -> Int {
        return 2
    }

    func didSelectRow(_ row: Int) {
        if row == 1 {
            let rootSettingsController = WindowHelper.shared.findFirstViewController(
                "RootSettingsViewController"
            )!
            
            let navigationController = rootSettingsController.navigationController!

            let iayxifySettingsController = IayxifySettingsViewController(
                rootSettingsController.view.bounds,
                settingsView: AnyView(IayxifySettingsView(navigationController: navigationController)),
                navigationTitle: "Iayxify"
            )
            
            //
            
            let button = UIButton()
            
            if let gitImage = BundleHelper.shared.uiImage("github") {
                button.setImage(gitImage.withRenderingMode(.alwaysOriginal), for: .normal)
            } else {
                button.setImage(UIImage(systemName: "globe"), for: .normal)
            }
            
            button.addTarget(
                iayxifySettingsController,
                action: #selector(iayxifySettingsController.openRepositoryUrl(_:)),
                for: .touchUpInside
            )
            
            //
            
            let menuBarItem = UIBarButtonItem(customView: button)
            
            menuBarItem.customView?.heightAnchor.constraint(equalToConstant: 22).isActive = true
            menuBarItem.customView?.widthAnchor.constraint(equalToConstant: 22).isActive = true

            iayxifySettingsController.navigationItem.rightBarButtonItem = menuBarItem
            
            navigationController.pushViewController(
                iayxifySettingsController,
                animated: true
            )

            return
        }

        orig.didSelectRow(row)
    }

    func cellForRow(_ row: Int) -> UITableViewCell {
        if row == 1 {
            let settingsTableCell = Dynamic.SPTSettingsTableViewCell
                .alloc(interface: SPTSettingsTableViewCell.self)
                .initWithStyle(3, reuseIdentifier: "Iayxify")
            
            let tableViewCell = Dynamic.convert(settingsTableCell, to: UITableViewCell.self)

            tableViewCell.accessoryView = type(
                of: Dynamic.SPTDisclosureAccessoryView
                    .alloc(interface: SPTDisclosureAccessoryView.self)
            )
            .disclosureAccessoryView()
            
            tableViewCell.textLabel?.text = "Iayxify"
            return tableViewCell
        }

        return orig.cellForRow(row)
    }
}
