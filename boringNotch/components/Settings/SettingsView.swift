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

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("通用", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("外观", systemImage: "eye")
                }
                NavigationLink(value: "Media") {
                    Label("媒体", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "Shelf") {
                    Label("文件架", systemImage: "books.vertical")
                }
                NavigationLink(value: "Clipboard") {
                    Label("剪贴板", systemImage: "clipboard")
                }
                NavigationLink(value: "Battery") {
                    Label("电池", systemImage: "battery.100")
                }
                NavigationLink(value: "HUD") {
                    Label("HUD", systemImage: "speaker.wave.2")
                }
                NavigationLink(value: "About") {
                    Label("关于", systemImage: "info.circle")
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
    }
}

/// Shared toolbar (quit button) so every settings page looks the same.
private extension View {
    func quitToolbar() -> some View {
        self.toolbar {
            Button("退出应用") {
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
                Defaults.Toggle(key: .menubarIcon) {
                    Text("显示菜单栏图标")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle("登录时启动")
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("在所有显示器上显示")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("首选显示器", selection: $coordinator.preferredScreenUUID) {
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
                    Text("自动切换显示器")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(
                        name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
            } header: {
                Text("系统功能")
            }

            Section {
                Picker(
                    selection: $notchHeightMode,
                    label:
                        Text("刘海高度（刘海屏）")
                ) {
                    Text("匹配真实刘海高度")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("匹配菜单栏高度")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("自定义高度")
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
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("自定义刘海高度 - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("刘海高度（非刘海屏）", selection: $nonNotchHeightMode) {
                    Text("匹配菜单栏高度")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("匹配真实刘海高度")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("自定义高度")
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
                        Text("自定义刘海高度 - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("刘海尺寸")
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
                Text("启用手势")
            }
            .disabled(!openNotchOnHover)
            if enableGestures {
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("关闭手势")
                }
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("手势灵敏度")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? "高" : Defaults[.gestureSensitivity] == 200 ? "中" : "低"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("手势控制")
        } footer: {
            Text(
                "在刘海双指上滑关闭，双指下滑打开（当 **悬停展开刘海** 关闭时生效）。\n剪贴板历史页签展开时下滑手势自动禁用，避免与滚动历史冲突。"
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
                Text("悬停展开刘海")
            }
            Defaults.Toggle(key: .enableHaptics) {
                Text("启用触感反馈")
            }
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("悬停延迟")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("刘海行为")
        }
    }
}

struct Appearance: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("在刘海显示设置图标")
                }
                Defaults.Toggle(key: .enableShadow) {
                    Text("启用阴影")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("展开时缩放圆角")
                }
            } header: {
                Text("通用")
            }

            Section {
                Defaults.Toggle(key: .useCustomAccentColor) {
                    Text("使用自定义强调色")
                }
            } header: {
                Text("强调色")
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
                Toggle("在刘海显示媒体状态", isOn: $coordinator.musicLiveActivityEnabled)
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("彩色频谱")
                }
            } header: {
                Text("媒体状态条")
            } footer: {
                Text("播放媒体时，刘海会显示当前曲目（封面 + 动态频谱）。")
            }

            Section {
                Slider(value: $waitInterval, in: 1...10, step: 1) {
                    Text("暂停后空闲超时 - \(waitInterval, specifier: "%.0f") 秒")
                }
            } header: {
                Text("空闲行为")
            } footer: {
                Text("播放暂停后，媒体状态条保留的时间。")
            }
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }
}

struct Shelf: View {
    @Default(.expandedDragDetection) var expandedDragDetection: Bool

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .boringShelf) {
                    Text("启用文件架")
                }
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("有文件时默认展开文件架")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("扩大拖拽检测区域")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("拖拽时复制文件")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("拖出后从文件架移除")
                }
            } header: {
                Text("通用")
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
                    Text("启用剪贴板历史")
                }
                Defaults.Toggle(key: .clipboardKeepImages) {
                    Text("记录图片")
                }
                .disabled(!historyEnabled)
                Defaults.Toggle(key: .clipboardKeepFiles) {
                    Text("记录文件引用")
                }
                .disabled(!historyEnabled)
            } header: {
                Text("通用")
            } footer: {
                Text("记录复制的文本、图片和文件引用，随时从历史中取回。文件只记录引用，不复制内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $maxItems, in: 5...50, step: 5) {
                    HStack {
                        Text("历史容量")
                        Spacer()
                        Text("\(maxItems) 条")
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("保留时长", selection: $retentionDays) {
                    Text("永不过期").tag(0)
                    Text("1 天").tag(1)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }
                Stepper(value: $maxItemSizeMB, in: 1...100, step: 1) {
                    HStack {
                        Text("单条大小上限")
                        Spacer()
                        Text("\(maxItemSizeMB) MB")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("容量")
            } footer: {
                Text("超出容量时自动淘汰最旧的记录；置顶（Pin）的记录不会被淘汰。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .clipboardHotkeyEnabled) {
                    Text("快捷键呼出快速面板（⌃⌥V）")
                }
                .disabled(!historyEnabled)
                Defaults.Toggle(key: .clipboardAutoPaste) {
                    Text("选中后自动粘贴到当前应用")
                }
                .disabled(!historyEnabled)
                .onChange(of: autoPaste) {
                    if autoPaste && !ClipboardQuickPanelController.isAccessibilityTrusted {
                        ClipboardQuickPanelController.shared.promptForAccessibility()
                    }
                }
            } header: {
                Text("快速面板")
            } footer: {
                Text("自动粘贴需要「辅助功能」权限；未授权时仅复制到剪贴板，可手动 ⌘V 粘贴。")
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
                    TextField("添加 Bundle ID（如 com.example.app）", text: $newIgnoredApp)
                        .textFieldStyle(.roundedBorder)
                    Button("添加") {
                        let id = newIgnoredApp.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !id.isEmpty, !ignoredApps.contains(id) else { return }
                        ignoredApps.append(id)
                        newIgnoredApp = ""
                    }
                    .disabled(newIgnoredApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("忽略的应用")
            } footer: {
                Text("来自这些应用的复制内容不会被记录。密码管理器（如 1Password）复制的内容始终自动跳过。")
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
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.systemEventIndicatorShadow) var systemEventIndicatorShadow
    @Default(.systemEventIndicatorUseAccent) var systemEventIndicatorUseAccent
    @Default(.showOpenNotchHUD) var showOpenNotchHUD
    @Default(.showOpenNotchHUDPercentage) var showOpenNotchHUDPercentage
    @Default(.showClosedNotchHUDPercentage) var showClosedNotchHUDPercentage
    @Default(.optionKeyAction) var optionKeyAction

    @State private var accessibilityAuthorized: Bool = false
    @State private var monitoringTimer: Timer?

    var body: some View {
        Form {
            Section {
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("需要辅助功能权限")
                            .font(.headline)
                        Text("HUD 替换需要辅助功能权限来拦截系统媒体键并抑制原生 bezel。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("请求权限") {
                                MediaKeyInterceptor.shared.requestAccessibilityAuthorization()
                            }
                            Button("打开系统设置") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                        Text("提示：若未弹出授权窗口（多因之前拒绝过或换过构建版本），请手动在「系统设置 ▸ 隐私与安全性 ▸ 辅助功能」中启用 DropNest，然后重启本 App 才能生效。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                Defaults.Toggle(key: .hudReplacement) {
                    Text("启用 HUD 替换")
                }
                .disabled(!accessibilityAuthorized)
            } header: {
                Text("主开关")
            } footer: {
                Text("启用后，按音量键时刘海会显示 HUD 而不是系统原生居中 bezel。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Option 键行为", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                Defaults.Toggle(key: .enableGradient) {
                    Text("渐变进度条")
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("进度条阴影")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("使用强调色")
                }
            } header: {
                Text("通用")
            }
            .disabled(!hudReplacement)

            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("展开态显示 HUD")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("展开态显示百分比")
                }
            } header: {
                Text("展开态")
            }
            .disabled(!hudReplacement)

            Section {
                Picker("折叠态样式", selection: Binding(
                    get: { inlineHUD ? "内联" : "默认" },
                    set: { Defaults[.inlineHUD] = ($0 == "内联") }
                )) {
                    Text("默认").tag("默认")
                    Text("内联").tag("内联")
                }
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("折叠态显示百分比")
                }
            } header: {
                Text("折叠态")
            }
            .disabled(!hudReplacement)
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("HUD")
        .task {
            accessibilityAuthorized = MediaKeyInterceptor.isAccessibilityTrusted
        }
        .onAppear {
            monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                let trusted = MediaKeyInterceptor.isAccessibilityTrusted
                accessibilityAuthorized = trusted
                // 授权到达后自动启动事件拦截（自愈：无需手动重开 App）
                if trusted {
                    Task { @MainActor in
                        await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                    }
                }
                if trusted {
                    monitoringTimer?.invalidate()
                    monitoringTimer = nil
                }
            }
        }
        .onDisappear {
            monitoringTimer?.invalidate()
            monitoringTimer = nil
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
                    Text("展开态显示电池指示器")
                }
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("显示百分比")
                }
                .disabled(!showBatteryIndicator)
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("显示充电/插电图标")
                }
                .disabled(!showBatteryIndicator)
            } header: {
                Text("展开态指示器")
            } footer: {
                Text("展开刘海时，在右上角显示电池图标和百分比。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("电源状态变化通知")
                }
            } header: {
                Text("折叠态通知")
            } footer: {
                Text("接入/断开电源、开始/停止充电、切换低电量模式时，刘海会短暂显示横向电池通知。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("当前电量")
                    Spacer()
                    Text("\(Int(batteryModel.levelBattery))%")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("最大容量")
                    Spacer()
                    Text("\(Int(batteryModel.maxCapacity))%")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("电源状态")
                    Spacer()
                    Text(batteryModel.isPluggedIn ? "已连接" : "使用电池")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("充电状态")
                    Spacer()
                    Text(batteryModel.isCharging ? "正在充电" : "未在充电")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("低电量模式")
                    Spacer()
                    Text(batteryModel.isInLowPowerMode ? "开" : "关")
                        .foregroundStyle(.secondary)
                }
                if batteryModel.timeToFullCharge > 0 {
                    HStack {
                        Text("充满剩余")
                        Spacer()
                        Text("\(batteryModel.timeToFullCharge) 分钟")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("实时状态")
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
                    Text("版本名称")
                    Spacer()
                    Text(Defaults[.releaseName])
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("版本")
                    Spacer()
                    if showBuildNumber {
                        Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                            .foregroundStyle(.secondary)
                    }
                    Text(Bundle.main.releaseVersionNumber ?? "unkown")
                        .foregroundStyle(.secondary)
                }
                .onTapGesture {
                    withAnimation {
                        showBuildNumber.toggle()
                    }
                }
            } header: {
                Text("版本信息")
            }
        }
        .quitToolbar()
        .accentColor(.effectiveAccent)
        .navigationTitle("About")
    }
}
