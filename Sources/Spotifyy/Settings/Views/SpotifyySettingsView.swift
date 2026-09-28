import SwiftUI
import UIKit

struct SpotifyySettingsView: View {
    let navigationController: UINavigationController

    /// Accent used by every Iayxify screen. Computed from the user's theme
    /// (`appearanceThemeOptions`) instead of being a constant, so the picker
    /// applies without touching the call sites.
    static var spotifyAccentColor: Color { SpotifyyAppearance.accentColor }
    
    @State private var hasShownCommonIssuesTip = UserDefaults.hasShownCommonIssuesTip
    @State private var isClearingData = false
    @State private var isPresentingDevNoteSheet = false

    /// Mirrored so the swatch strip redraws the moment a theme is tapped; the
    /// real value lives in `UserDefaults.appearanceThemeOptions`.
    @State private var themeOptions = UserDefaults.appearanceThemeOptions

    /// Same mirroring for the inline feature switches at the bottom.
    @State private var cleanShareLinks = UserDefaults.cleanShareLinks
    @State private var darkPopUps = UserDefaults.darkPopUps
    @State private var sponsorBlockEnabled = UserDefaults.sponsorBlockOptions.enabled
    @State private var listeningStatsEnabled = UserDefaults.listeningStatsEnabled
    @State private var trueShuffle = UserDefaults.trueShuffleEnabled
    @State private var prettifyIconNames = UserDefaults.iconNamePrettify
    /// Bumped when the accent changes. This view stays alive underneath the
    /// Appearance screen, so the notification reaches it while it is off-screen
    /// and this forced rebuild makes the accent-tinted rows correct when the
    /// user pops back instead of still showing the old colour.
    @State private var appearanceRevision = 0


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
        let viewController = SpotifyySettingsViewController(
            navigationController.view.frame,
            settingsView: AnyView(view),
            navigationTitle: title
        )
        navigationController.pushViewController(viewController, animated: true)
    }
    
    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        // Honours the user's accent (and their 'tint Spotify controls' toggle).
        SpotifyyAppearance.applyToSystemControls()
    }

    var body: some View {
        List {
            SpotifyySettingsVersionView()
            
            if !hasShownCommonIssuesTip {
                CommonIssuesTipView(
                    onDismiss: {
                        hasShownCommonIssuesTip = true
                        UserDefaults.hasShownCommonIssuesTip = true
                    }
                )
            }

            themeSwatchSection

            //
            
            Button {
                pushSettingsController(
                    with: SpotifyyPatchingSettingsView(),
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
                    with: SpotifyyLyricsSettingsView(),
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
                    with: SpotifyyUISettingsView(),
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
                    with: SpotifyyAppearanceSettingsView(),
                    title: "appearance".localized
                )
            } label: {
                NavigationSectionView(
                    color: Color(hex: "#00C7BE"),
                    title: "appearance".localized,
                    imageSystemName: "paintbrush.fill"
                )
            }

            Button {
                pushSettingsController(
                    with: SpotifyyExperimentsSettingsView(),
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
                    with: SpotifyySleepTimerSettingsView(),
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
                    with: SpotifyyListeningStatsView(),
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
                    with: SpotifyyAppIconPickerView(),
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
                    with: SpotifyyMiscellaneousSettingsView(),
                    title: "miscellaneous".localized
                )
            } label: {
                NavigationSectionView(
                    color: .gray,
                    title: "miscellaneous".localized,
                    imageSystemName: "ellipsis.circle.fill"
                )
            }

            featureTogglesSection

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
                SpotifyyDevNoteView()
            }

            Section(header: Text("debug_title".localized), footer: Text("debug_section_footer".localized)) {
                Button {
                    let logPath = NSTemporaryDirectory() + "spotifyy_debug.log"
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
                    let logPath = NSTemporaryDirectory() + "spotifyy_debug.log"
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
        .id(appearanceRevision)
        
        .animation(.default, value: isClearingData)
        .animation(.default, value: hasShownCommonIssuesTip)

        .onAppear {
            themeOptions = UserDefaults.appearanceThemeOptions
            WindowHelper.shared.overrideUserInterfaceStyle(SpotifyyAppearance.palette.style)
        }
        .onReceive(NotificationCenter.default.publisher(for: .spotifyyAppearanceChanged)) { _ in
            themeOptions = UserDefaults.appearanceThemeOptions
            appearanceRevision &+= 1
        }
    }

    // MARK: - Theme

    /// Theme presets inline, so the hub can recolour the app without a second
    /// navigation step. "Custom" opens the theme screen, where the colour
    /// pickers live.
    private var themeSwatchSection: some View {
        Section(
            header: Text("theme_quick_section".localized),
            footer: Text("theme_quick_footer".localized)
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(IayxifyTheme.allCases, id: \.self) { theme in
                        swatch(theme)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func swatch(_ theme: IayxifyTheme) -> some View {
        let palette = theme.palette(custom: themeOptions.custom)
        let isSelected = themeOptions.theme == theme

        return Button {
            selectTheme(theme)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [palette.background, palette.accent]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .overlay(
                            Circle().stroke(
                                isSelected ? SpotifyySettingsView.spotifyAccentColor : Color.white.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                        )

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    }
                }
                .frame(height: 48)

                Text(theme.localizationKey.localized)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 62)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func selectTheme(_ theme: IayxifyTheme) {
        var updated = themeOptions
        updated.theme = theme
        themeOptions = updated
        UserDefaults.appearanceThemeOptions = updated

        SpotifyyAppearance.applyToSystemControls()
        SpotifyyAppearance.refreshScreenAppearance()
        SpotifyyAppearance.notifyChanged(debounced: false)

        // The colour pickers live on the theme screen, so tapping Custom takes
        // the user there instead of applying an invisible preset.
        if theme.isCustom {
            pushSettingsController(
                with: SpotifyyAppearanceSettingsView(),
                title: "appearance".localized
            )
        }
    }

    // MARK: - Feature switches

    /// The switches that are read on every use, so they can be flipped from here
    /// and take effect immediately. Features that install hooks at launch live in
    /// their own sections, since those need a restart.
    private var featureTogglesSection: some View {
        Section(
            header: Text("features_section".localized),
            footer: Text("features_footer".localized)
        ) {
            Toggle(isOn: Binding(
                get: { cleanShareLinks },
                set: { newValue in
                    cleanShareLinks = newValue
                    UserDefaults.cleanShareLinks = newValue
                }
            )) {
                Text("features_clean_share_links".localized)
            }

            Toggle(isOn: Binding(
                get: { sponsorBlockEnabled },
                set: { newValue in
                    sponsorBlockEnabled = newValue
                    var options = UserDefaults.sponsorBlockOptions
                    options.enabled = newValue
                    UserDefaults.sponsorBlockOptions = options
                }
            )) {
                Text("sponsorblock".localized)
            }

            Toggle(isOn: Binding(
                get: { listeningStatsEnabled },
                set: { newValue in
                    listeningStatsEnabled = newValue
                    UserDefaults.listeningStatsEnabled = newValue
                }
            )) {
                Text("listening_stats_enabled".localized)
            }

            Toggle(isOn: Binding(
                get: { trueShuffle },
                set: { newValue in
                    trueShuffle = newValue
                    UserDefaults.trueShuffleEnabled = newValue
                }
            )) {
                Text("true_shuffle".localized)
            }

            Toggle(isOn: Binding(
                get: { prettifyIconNames },
                set: { newValue in
                    prettifyIconNames = newValue
                    UserDefaults.iconNamePrettify = newValue
                }
            )) {
                Text("prettifyIconNames".localized)
            }

            Toggle(isOn: Binding(
                get: { darkPopUps },
                set: { newValue in
                    darkPopUps = newValue
                    UserDefaults.darkPopUps = newValue
                }
            )) {
                Text("dark_popups".localized)
            }

            Text("features_restart_note".localized)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
