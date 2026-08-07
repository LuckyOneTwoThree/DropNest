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
        .toolbar {
            Button("退出应用") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
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
                "在刘海双指上滑关闭，双指下滑打开（当 **悬停展开刘海** 关闭时生效）"
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
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
    }
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    var body: some View {
        VStack {
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
            VStack(spacing: 0) {
                Divider()
                Text("精简版 —— 文件架 + 正在播放")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("About")
    }
}
