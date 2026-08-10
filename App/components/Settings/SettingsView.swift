//
//  SettingsView.swift
//  DropNest
//
//  Created by Richard Kunkli on 07/08/2024.
//  Trimmed: General / Appearance / Media / Shelf / About only (2026-08-07).
//

import Defaults
import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = "General"
    @ObservedObject var languageManager = LanguageManager.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(value: "Media") {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "Shelf") {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(value: "Clipboard") {
                    Label("Clipboard", systemImage: "clipboard")
                }
                NavigationLink(value: "Battery") {
                    Label("Battery", systemImage: "battery.100")
                }
                NavigationLink(value: "HUD") {
                    Label("HUD", systemImage: "speaker.wave.2")
                }
                NavigationLink(value: "About") {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "Shelf":
                    Shelf()
                case "Clipboard":
                    ClipboardSettings()
                case "Battery":
                    BatterySettings()
                case "HUD":
                    HUDSettings()
                case "About":
                    About()
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .environment(\.locale, languageManager.currentLocale)
    }
}

/// Shared toolbar (quit button) so every settings page looks the same.
private extension View {
    func quitToolbar() -> some View {
        self.toolbar {
            Button("Quit Application") {
                NSApp.terminate(nil)
            }
            .controlSize(.extraLarge)
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @ObservedObject var languageManager = LanguageManager.shared

    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover

    var body: some View {
        Form {
            Section {
                Picker("App Language", selection: $languageManager.currentLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.localizedTitle).tag(lang)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Language")
            }

            Section {
                Defaults.Toggle(key: .menubarIcon) {
                    Text("Show Menu Bar Icon")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle(String(localized: "Launch at Login", locale: LanguageManager.shared.currentLocale))
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on All Displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("Preferred Display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)

                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Auto Switch Display")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(
                        name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
            } header: {
                Text("System Features")
            }

            Section {
                Picker(
                    selection: $notchHeightMode,
                    label:
                        Text("Notch Height (Notch Displays)")
                ) {
                    Text("Match Real Notch Height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match Menu Bar Height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom Height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        notchHeight = 38
                    case .matchMenuBar:
                        notchHeight = 44
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 0...60, step: 1) {
                        Text(String(format: String(localized: "Custom Notch Height: %d pt", locale: LanguageManager.shared.currentLocale), Int(notchHeight)))
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Notch Height (Non-Notch Displays)", selection: $nonNotchHeightMode) {
                    Text("Match Menu Bar Height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match Real Notch Height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom Height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text(String(format: String(localized: "Custom Notch Height: %d pt", locale: LanguageManager.shared.currentLocale), Int(nonNotchHeight)))
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch Dimensions")
            }

            NotchBehaviour()
            gestureControls()
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("General")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable Gestures")
            }
            .disabled(!openNotchOnHover)
            if enableGestures {
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Disable Gestures")
                }
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture Sensitivity")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? String(localized: "High", locale: LanguageManager.shared.currentLocale) : Defaults[.gestureSensitivity] == 200 ? String(localized: "Medium", locale: LanguageManager.shared.currentLocale) : String(localized: "Low", locale: LanguageManager.shared.currentLocale)
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Gesture Control")
        } footer: {
            Text(
                "Swipe up with two fingers on notch to close, swipe down to open (effective when **Hover to Expand Notch** is disabled).\nSwipe down gesture is automatically disabled when Clipboard History tab is expanded to avoid scrolling conflict."
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Hover to Expand Notch")
            }
            Defaults.Toggle(key: .enableHaptics) {
                Text("Enable Haptic Feedback")
            }
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Hover Delay")
                        Spacer()
                        Text(String(format: String(localized: "%.1f s", locale: LanguageManager.shared.currentLocale), minimumHoverDuration))
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch Behavior")
        }
    }
}

struct Appearance: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show Settings Icon in Notch")
                }
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable Shadow")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Scale Corner Radius When Expanded")
                }
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .useCustomAccentColor) {
                    Text("Use Custom Accent Color")
                }
            } header: {
                Text("Accent Color")
            }
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }
}

struct Media: View {
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @Default(.coloredSpectrogram) var coloredSpectrogram
    @Default(.waitInterval) var waitInterval

    var body: some View {
        Form {
            Section {
                Toggle("Show Media Status in Notch", isOn: $coordinator.musicLiveActivityEnabled)
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colorful Spectrum")
                }
            } header: {
                Text("Media Status Bar")
            } footer: {
                Text("When playing media, the notch will display current track (cover + dynamic spectrum).")
            }

            Section {
                Slider(value: $waitInterval, in: 1...10, step: 1) {
                    Text(String(format: String(localized: "Idle Timeout After Pause: %d seconds", locale: LanguageManager.shared.currentLocale), Int(waitInterval)))
                }
            } header: {
                Text("Idle Behavior")
            } footer: {
                Text("Duration media status bar remains visible after playback is paused.")
            }
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }
}

struct Shelf: View {
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @Default(.floatingNestEnabled) var floatingNestEnabled: Bool
    @Default(.nestShowOnDragStart) var nestShowOnDragStart: Bool
    @Default(.shakeSensitivity) var shakeSensitivity: Double
    @Default(.nestMaxGridColumns) var nestMaxGridColumns: Int

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boringShelf) {
                    Text("Enable Shelf")
                }
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Expand Shelf by Default When Files Exist")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expand Drag Detection Region")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Copy Files on Drag")
                        Text("Enabled (default): Copy files to destination when dragging out temporary files; original files remain in place.\nDisabled: Move original files when dragging out (equivalent to cut).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from Shelf After Dragging Out")
                }
            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .floatingNestEnabled) {
                    Text("Enable Floating Nests")
                }
                Defaults.Toggle(key: .nestShowOnDragStart) {
                    Text("Auto Show Nest Group on Drag Start")
                }
                .disabled(!floatingNestEnabled)
                Slider(value: $shakeSensitivity, in: 0...1, step: 0.1) {
                    Text(String(format: String(localized: "Shake Sensitivity: %.1f", locale: LanguageManager.shared.currentLocale), shakeSensitivity))
                }
                .disabled(!floatingNestEnabled)
                Stepper(value: $nestMaxGridColumns, in: 2...4) {
                    HStack {
                        Text("Max Grid Columns")
                        Spacer()
                        Text("\(nestMaxGridColumns) × \(nestMaxGridColumns)")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!floatingNestEnabled)
                Defaults.Toggle(key: .nestAutoGroupOnBatchDrop) {
                    Text("Auto Group Batch Drops")
                }
            } header: {
                Text("Floating Nests and Groups")
            } footer: {
                Text("Each floating nest = one group. Automatically displays empty nest indicator near cursor when drag starts, dropping hatches into a full nest; when auto show on drag start is disabled, invoke via mouse shake. Max grid columns controls max width of a nest.")
            }
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
    }
}

struct ClipboardSettings: View {
    @Default(.clipboardHistoryEnabled) var historyEnabled
    @Default(.clipboardKeepImages) var keepImages
    @Default(.clipboardKeepFiles) var keepFiles
    @Default(.clipboardMaxItems) var maxItems
    @Default(.clipboardRetentionDays) var retentionDays
    @Default(.clipboardMaxItemSizeMB) var maxItemSizeMB
    @Default(.clipboardIgnoredApps) var ignoredApps
    @Default(.clipboardHotkeyEnabled) var hotkeyEnabled
    @Default(.clipboardAutoPaste) var autoPaste

    @State private var newIgnoredApp: String = ""

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .clipboardHistoryEnabled) {
                    Text("Enable Clipboard History")
                }
                Defaults.Toggle(key: .clipboardKeepImages) {
                    Text("Record Images")
                }
                .disabled(!historyEnabled)
                Defaults.Toggle(key: .clipboardKeepFiles) {
                    Text("Record File References")
                }
                .disabled(!historyEnabled)
            } header: {
                Text("General")
            } footer: {
                Text("Records copied text, images, and file references, allowing retrieval anytime from history. Files record references only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $maxItems, in: 5...50, step: 5) {
                    HStack {
                        Text("History Capacity")
                        Spacer()
                        Text("\(maxItems) items")
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Retention Duration", selection: $retentionDays) {
                    Text("Never").tag(0)
                    Text("1 Day").tag(1)
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                }
                Stepper(value: $maxItemSizeMB, in: 1...100, step: 1) {
                    HStack {
                        Text("Single Item Size Limit")
                        Spacer()
                        Text("\(maxItemSizeMB) MB")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Capacity")
            } footer: {
                Text("Oldest entries are automatically purged when capacity is exceeded; Pinned entries are never purged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .clipboardHotkeyEnabled) {
                    Text("Summon Quick Panel with Hotkey (⌃⌥V)")
                }
                .disabled(!historyEnabled)
                Defaults.Toggle(key: .clipboardAutoPaste) {
                    Text("Auto Paste to Active App When Selected")
                }
                .disabled(!historyEnabled)
                .onChange(of: autoPaste) {
                    if autoPaste && !ClipboardQuickPanelController.isAccessibilityTrusted {
                        ClipboardQuickPanelController.shared.promptForAccessibility()
                    }
                }
            } header: {
                Text("Quick Panel")
            } footer: {
                Text("Auto paste requires Accessibility permission; when ungranted, items are copied to clipboard for manual ⌘V paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ignoredApps, id: \.self) { bundleID in
                    HStack {
                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(appURL.deletingPathExtension().lastPathComponent)
                            Text(bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "app.dashed")
                                .frame(width: 16, height: 16)
                            Text(bundleID)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            ignoredApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Add Bundle ID (e.g. com.example.app)", text: $newIgnoredApp)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let id = newIgnoredApp.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !id.isEmpty, !ignoredApps.contains(id) else { return }
                        ignoredApps.append(id)
                        newIgnoredApp = ""
                    }
                    .disabled(newIgnoredApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Ignored Applications")
            } footer: {
                Text("Copies from these applications will not be recorded. Password managers (e.g. 1Password) are always automatically skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("Clipboard")
    }
}

struct HUDSettings: View {
    @Default(.hudReplacement) var hudReplacement
    @Default(.volumeHUDEnabled) var volumeHUDEnabled
    @Default(.brightnessHUDEnabled) var brightnessHUDEnabled
    @Default(.keyboardBacklightHUDEnabled) var keyboardBacklightHUDEnabled
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.systemEventIndicatorShadow) var systemEventIndicatorShadow
    @Default(.systemEventIndicatorUseAccent) var systemEventIndicatorUseAccent
    @Default(.showOpenNotchHUD) var showOpenNotchHUD
    @Default(.showOpenNotchHUDPercentage) var showOpenNotchHUDPercentage
    @Default(.showClosedNotchHUDPercentage) var showClosedNotchHUDPercentage
    @Default(.optionKeyAction) var optionKeyAction

    @State private var accessibilityAuthorized: Bool = false

    var body: some View {
        Form {
            Section {
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility Permission Required")
                            .font(.headline)
                        Text("HUD replacement requires Accessibility permission to intercept system media keys and suppress native bezel.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Request Permission") {
                                MediaKeyInterceptor.shared.requestAccessibilityAuthorization()
                            }
                            Button("Open System Settings") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        Text("Tip: If the authorization window does not appear, please manually enable DropNest under System Settings ▸ Privacy & Security ▸ Accessibility, then restart this App.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                Defaults.Toggle(key: .hudReplacement) {
                    Text("Enable HUD Replacement")
                }
                .disabled(!accessibilityAuthorized)
            } header: {
                Text("Main Switch")
            } footer: {
                Text("When enabled, pressing volume keys will show HUD in Notch instead of system native centered bezel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .volumeHUDEnabled) {
                    Text("Volume HUD")
                }
                Defaults.Toggle(key: .brightnessHUDEnabled) {
                    Text("Brightness HUD")
                }
                Defaults.Toggle(key: .keyboardBacklightHUDEnabled) {
                    Text("Keyboard Backlight HUD")
                }
            } header: {
                Text("Feature Toggles")
            } footer: {
                Text("Individually control key interception and HUD display per category. Disabled categories pass through native events.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!hudReplacement)

            Section {
                Picker("Option Key Behavior", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { action in
                        Text(action.localizedTitle).tag(action)
                    }
                }
                Defaults.Toggle(key: .enableGradient) {
                    Text("Gradient Progress Bar")
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Progress Bar Shadow")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Use Accent Color")
                }
            } header: {
                Text("General")
            }
            .disabled(!hudReplacement)

            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("Show HUD in Expanded State")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("Show Percentage in Expanded State")
                }
            } header: {
                Text("Expanded State")
            }
            .disabled(!hudReplacement)

            Section {
                Picker("Collapsed Style", selection: Binding(
                    get: { inlineHUD ? "Inline" : "Default" },
                    set: { Defaults[.inlineHUD] = ($0 == "Inline") }
                )) {
                    Text(String(localized: "Default", locale: LanguageManager.shared.currentLocale)).tag("Default")
                    Text(String(localized: "Inline", locale: LanguageManager.shared.currentLocale)).tag("Inline")
                }
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Show Percentage in Collapsed State")
                }
            } header: {
                Text("Collapsed State")
            }
            .disabled(!hudReplacement)
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("HUD")
        .task {
            accessibilityAuthorized = MediaKeyInterceptor.isAccessibilityTrusted
            guard !accessibilityAuthorized else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                let trusted = MediaKeyInterceptor.isAccessibilityTrusted
                accessibilityAuthorized = trusted
                if trusted {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                    return
                }
            }
        }
    }
}

struct BatterySettings: View {
    @Default(.showPowerStatusNotifications) var showPowerStatusNotifications
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showBatteryPercentage) var showBatteryPercentage
    @Default(.showPowerStatusIcons) var showPowerStatusIcons
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Show Battery Indicator in Expanded State")
                }
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("Show Percentage")
                }
                .disabled(!showBatteryIndicator)
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Show Charging/Plug Icon")
                }
                .disabled(!showBatteryIndicator)
            } header: {
                Text("Expanded State Indicator")
            } footer: {
                Text("Displays battery icon and percentage in top right when expanding notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Power Status Change Notification")
                }
            } header: {
                Text("Collapsed State Notification")
            } footer: {
                Text("Notch briefly displays horizontal battery notification when connecting/disconnecting power, starting/stopping charging, or toggling low power mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Current Level")
                    Spacer()
                    Text("\(Int(batteryModel.levelBattery))%")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Max Capacity")
                    Spacer()
                    Text("\(Int(batteryModel.maxCapacity))%")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Power Source")
                    Spacer()
                    Text(batteryModel.isPluggedIn ? String(localized: "Connected", locale: LanguageManager.shared.currentLocale) : String(localized: "On Battery", locale: LanguageManager.shared.currentLocale))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Charging Status")
                    Spacer()
                    Text(batteryModel.isCharging ? String(localized: "Charging", locale: LanguageManager.shared.currentLocale) : String(localized: "Not Charging", locale: LanguageManager.shared.currentLocale))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Low Power Mode")
                    Spacer()
                    Text(batteryModel.isInLowPowerMode ? String(localized: "On", locale: LanguageManager.shared.currentLocale) : String(localized: "Off", locale: LanguageManager.shared.currentLocale))
                        .foregroundStyle(.secondary)
                }
                if batteryModel.timeToFullCharge > 0 {
                    HStack {
                        Text("Time Until Full")
                        Spacer()
                        Text(String(format: String(localized: "%d minutes", locale: LanguageManager.shared.currentLocale), batteryModel.timeToFullCharge))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Real-Time Status")
            }
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("Battery")
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Release Name")
                    Spacer()
                    Text(Defaults[.releaseName])
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Version")
                    Spacer()
                    if showBuildNumber {
                        Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                            .foregroundStyle(.secondary)
                    }
                    Text(Bundle.main.releaseVersionNumber ?? String(localized: "Unknown", locale: LanguageManager.shared.currentLocale))
                        .foregroundStyle(.secondary)
                }
                .onTapGesture {
                    withAnimation {
                        showBuildNumber.toggle()
                    }
                }
            } header: {
                Text("Version Information")
            }
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("About")
    }
}
