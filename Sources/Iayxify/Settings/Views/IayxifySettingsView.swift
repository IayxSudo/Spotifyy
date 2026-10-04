import SwiftUI
import UIKit

struct IayxifySettingsView: View {
    let navigationController: UINavigationController

    /// The accent Iayxify's own screens use. Named for Spotify green because
    /// every call site predates the theme engine; it now follows the theme.
    static var spotifyAccentColor: Color { IayxifyAppearance.accentColor }
    
    @State private var hasShownCommonIssuesTip = UserDefaults.hasShownCommonIssuesTip
    @State private var isClearingData = false
    @State private var isPresentingDevNoteSheet = false
    @State private var appearanceOptions = UserDefaults.appearanceThemeOptions


    private func confirmDestructive(
        title: String,
        message: String,
        confirmTitle: String,
        onConfirm: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel".uiKitLocalized, style: .cancel))
        alert.addAction(UIAlertAction(title: confirmTitle, style: .destructive) { _ in
            onConfirm()
        })
        WindowHelper.shared.present(alert)
    }

    private func pushSettingsController(with view: any View, title: String) {
        let viewController = IayxifySettingsViewController(
            navigationController.view.frame,
            settingsView: AnyView(view),
            navigationTitle: title
        )
        navigationController.pushViewController(viewController, animated: true)
    }
    
    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        // Push the theme into UIKit's appearance proxies once, before the first
        // screen is built; the engine keeps every view after that in sync.
        IayxifyAppearance.applyToSystemControls()
    }

    // MARK: - Theme quick picker

    private func themeSwatch(_ theme: IayxifyTheme) -> some View {
        let swatch = theme.palette(custom: appearanceOptions.custom)
        let isSelected = appearanceOptions.theme == theme

        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [swatch.background, swatch.accent]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)

                Circle()
                    .stroke(swatch.accent, lineWidth: 2)
                    .frame(width: 42, height: 42)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: 44, height: 44)

            Text(theme.localizationKey.localized)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func selectTheme(_ theme: IayxifyTheme) {
        appearanceOptions.theme = theme
        UserDefaults.appearanceThemeOptions = appearanceOptions
        IayxifyAppearance.applyToSystemControls()
        IayxifyAppearance.refreshScreenAppearance()
        IayxifyAppearance.notifyChanged(debounced: false)
    }

    var body: some View {
        List {
            IayxifySettingsVersionView()
            
            if !hasShownCommonIssuesTip {
                CommonIssuesTipView(
                    onDismiss: {
                        hasShownCommonIssuesTip = true
                        UserDefaults.hasShownCommonIssuesTip = true
                    }
                )
            }
            
            //
            
            Section(
                header: Text("theme_quick_section".localized),
                footer: Text("theme_quick_footer".localized)
            ) {
                HStack(spacing: 4) {
                    ForEach(IayxifyTheme.allCases, id: \.self) { theme in
                        Button {
                            selectTheme(theme)
                        } label: {
                            themeSwatch(theme)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.vertical, 2)

                Button {
                    pushSettingsController(
                        with: IayxifyAppearanceSettingsView(),
                        title: "appearance".localized
                    )
                } label: {
                    NavigationSectionView(
                        color: Color(hex: "#64D2FF"),
                        title: "appearance".localized,
                        imageSystemName: "paintpalette.fill"
                    )
                }
            }
            
            Button {
                pushSettingsController(
                    with: IayxifyPatchingSettingsView(),
                    title: "patching".localized
                )
            } label: {
                NavigationSectionView(
                    color: .orange,
                    title: "patching".localized,
                    imageSystemName: "hammer.fill"
                )
            }
            
            Button {
                pushSettingsController(
                    with: IayxifyLyricsSettingsView(),
                    title: "lyrics".localized
                )
            } label: {
                NavigationSectionView(
                    color: .blue,
                    title: "lyrics".localized,
                    imageSystemName: "quote.bubble.fill"
                )
            }
            
            Button {
                pushSettingsController(
                    with: IayxifyUISettingsView(),
                    title: "customization".localized
                )
            } label: {
                NavigationSectionView(
                    color: Color(hex: "#64D2FF"),
                    title: "customization".localized,
                    imageSystemName: "paintpalette.fill"
                )
            }
            
            Button {
                pushSettingsController(
                    with: IayxifyExperimentsSettingsView(),
                    title: "experiments".localized
                )
            } label: {
                NavigationSectionView(
                    color: .purple,
                    title: "experiments".localized,
                    imageSystemName: "sparkle"
                )
            }

            Button {
                pushSettingsController(
                    with: IayxifySleepTimerSettingsView(),
                    title: "sleepTimer".localized
                )
            } label: {
                NavigationSectionView(
                    color: Color(hex: "#5E5CE6"),
                    title: "sleepTimer".localized,
                    imageSystemName: "moon.zzz.fill"
                )
            }

            Button {
                pushSettingsController(
                    with: IayxifyListeningStatsView(),
                    title: "listeningStats".localized
                )
            } label: {
                NavigationSectionView(
                    color: Color(hex: "#30D158"),
                    title: "listeningStats".localized,
                    imageSystemName: "chart.bar.fill"
                )
            }

            Button {
                pushSettingsController(
                    with: SponsorBlockSettingsView(),
                    title: "sponsorblock".localized
                )
            } label: {
                NavigationSectionView(
                    color: .red,
                    title: "sponsorblock".localized,
                    imageSystemName: "forward.end.fill"
                )
            }

            Button {
                pushSettingsController(
                    with: IayxifyAppIconPickerView(),
                    title: "appIcon".localized
                )
            } label: {
                NavigationSectionView(
                    color: .pink,
                    title: "appIcon".localized,
                    imageSystemName: "app.badge.fill"
                )
            }

            Button {
                pushSettingsController(
                    with: IayxifyMiscellaneousSettingsView(),
                    title: "miscellaneous".localized
                )
            } label: {
                NavigationSectionView(
                    color: .gray,
                    title: "miscellaneous".localized,
                    imageSystemName: "ellipsis.circle.fill"
                )
            }

            //

            Section {
                Button {
                    isPresentingDevNoteSheet = true
                } label: {
                    HStack {
                        Image(systemName: "person.fill.questionmark")
                        Text("\("developer_note".localized)...")
                    }
                }
            }
            .sheet(isPresented: $isPresentingDevNoteSheet) {
                IayxifyDevNoteView()
            }

            Section(header: Text("debug_title".localized), footer: Text("debug_section_footer".localized)) {
                Button {
                    let logPath = NSTemporaryDirectory() + "iayxify_debug.log"
                    guard FileManager.default.fileExists(atPath: logPath),
                          let logData = FileManager.default.contents(atPath: logPath),
                          logData.count > 0 else {
                        PopUpHelper.showPopUp(message: "no_debug_log_found".localized, buttonText: "no_debug_log_found_ok".localized)
                        return
                    }
                    let logURL = URL(fileURLWithPath: logPath)
                    let activityVC = UIActivityViewController(activityItems: [logURL], applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = scene.windows.first?.rootViewController {
                        var topVC = rootVC
                        while let presented = topVC.presentedViewController { topVC = presented }
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = topVC.view
                            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                        }
                        topVC.present(activityVC, animated: true)
                    }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("export_debug_log".localized)
                    }
                }
                
                Button {
                    let logPath = NSTemporaryDirectory() + "iayxify_debug.log"
                    try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
                    writeDebugLog("Log cleared by user")
                    PopUpHelper.showPopUp(message: "debug_log_cleared".localized, buttonText: "debug_log_cleared_ok".localized)
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("clear_debug_log".localized)
                    }
                    .foregroundColor(.red)
                }
            }
            
            Section(footer: Text("reset_data_description".localized)) {
                Button {
                    confirmDestructive(
                        title: "reset_data".localized,
                        message: "reset_data_description".localized,
                        confirmTitle: "reset_data".localized
                    ) {
                        isClearingData = true

                        DispatchQueue.global(qos: .userInitiated).async {
                            OfflineHelper.resetData(clearCaches: true)

                            DispatchQueue.main.async {
                                exitApplication()
                            }
                        }
                    }
                } label: {
                    if isClearingData {
                        ProgressView()
                    }
                    else {
                        Text("reset_data".localized)
                    }
                }
            }

            Section(footer: Text("resetFooter".localized)) {
                Button {
                    confirmDestructive(
                        title: "resetButtonTitle".localized,
                        message: "resetSubtitle".localized,
                        confirmTitle: "resetButtonTitle".localized
                    ) {
                        isClearingData = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            FullResetHelper.wipeSpotifyState()
                            DispatchQueue.main.async {
                                exitApplication()
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("resetButtonTitle".localized)
                    }
                    .foregroundColor(.red)
                }
            }

            Section {
                Color.clear
                    .frame(height: 90)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(GroupedListStyle())
        
        .animation(.default, value: isClearingData)
        .animation(.default, value: hasShownCommonIssuesTip)

        .onAppear {
            // The window style and the app-wide repaint are the engine's job;
            // this just makes sure the screen that is opening picks them up.
            IayxifyAppearance.refreshScreenAppearance()
        }
    }
}
