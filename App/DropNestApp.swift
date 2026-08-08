//
//  DropNestApp.swift
//  DropNestApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//  Trimmed: no Sparkle / onboarding / XPC helper (2026-08-07).
//

import Defaults
import SwiftUI

@main
struct DropNestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon

    var body: some Scene {
        MenuBarExtra("DropNest", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("设置") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            Divider()
            Button("重启 DropNest") {
                ApplicationRelauncher.restart()
            }
            Button("退出", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: NotchViewModel] = [:] // UUID -> NotchViewModel
    var window: NSWindow?
    let vm: NotchViewModel = .init()
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    /// 闭包式 NotificationCenter observer token 集中存放，退出时统一注销
    private var notificationObservers: [Any] = []
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var windowObservers: [NSWindow: Any] = [:] // NSWindow -> Observer Token

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        // 退出前立即将货架数据落盘，避免异步 saveTask 被终止而丢失。
        ShelfPersistenceService.shared.saveImmediately(ShelfStateViewModel.shared.items)

        NotificationCenter.default.removeObserver(self)
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        // 释放「复制」持有的安全作用域资源，避免退出前泄漏
        ShelfItemViewModel.releaseCopiedURLs()
        // 清理摇晃检测器采样与悬浮暂存巢群
        ShakeGestureDetector.shared.reset()
        FloatingNestManager.shared.cleanup()
        cleanupDragDetectors()
        cleanupWindows()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }

    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? NotchSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? NotchSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }

    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? NotchSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? NotchSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]

        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
                if let obs = windowObservers[window] {
                    NotificationCenter.default.removeObserver(obs)
                    windowObservers.removeValue(forKey: window)
                }
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowObservers[window] {
                NotificationCenter.default.removeObserver(obs)
                windowObservers.removeValue(forKey: window)
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }

        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width

        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )

        let detector = DragDetector(notchRegion: notchRegion)

        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }

        // 摇晃召唤悬浮暂存框（R2）：拖拽移动采样喂入检测器；离开刘海区域/拖拽结束时重置
        // DragDetector 已是 @MainActor，这里同步喂样本：
        // 既省掉每次移动事件的 Task 分配，也保证采样时间戳取自事件发生时刻而非调度时刻
        detector.onDragMove = { point in
            ShakeGestureDetector.shared.feed(point)
        }

        // v2.1：内容拖拽开始 → 创建空巢胚；结束 → 清理未使用的空巢胚
        detector.onContentDragStart = { point in
            Task { @MainActor in
                FloatingNestManager.shared.handleDragStart(at: point)
            }
        }
        detector.onContentDragEnd = {
            Task { @MainActor in
                FloatingNestManager.shared.handleDragEnd()
                ShakeGestureDetector.shared.reset()
            }
        }

        detector.onDragExitsNotchRegion = {
            Task { @MainActor in
                ShakeGestureDetector.shared.reset()
            }
        }

        detector.onDragEnd = {
            Task { @MainActor in
                ShakeGestureDetector.shared.reset()
            }
        }

        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }

        // A drag into the notch is a shelf-deposit intent: always show the shelf tab.
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.openTab = .shelf
            viewModel.open()
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.openTab = .shelf
            vm.open()
        }
    }

    private func createNotchWindow(for screen: NSScreen, with viewModel: NotchViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]

        let window = NotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)

        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors.
        // 先移除旧 observer，避免重复创建窗口时泄漏。
        if let old = windowObservers[window] {
            NotificationCenter.default.removeObserver(old)
        }
        windowObservers[window] = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    // MARK: - 单实例保护

    /// 终止同 bundle id 的其他运行实例，保留当前（最新）实例。
    /// 防止多实例并发读写同一容器内的 items.json / blobs 造成数据损坏。
    private func enforceSingleInstance() {
        let mine = ProcessInfo.processInfo.processIdentifier
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where app.processIdentifier != mine {
            app.terminate()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护：多个实例共享同一沙盒容器，并发读写 items.json/blobs 会互相踩踏
        // （实测出现过 prune 删 blob 而另一实例仍引用 → 图片缩略图丢失）。保留最新启动的实例。
        enforceSingleInstance()

        // Trimmed build removed the onboarding flow; mark first launch as complete
        // so hover-to-open in ContentView is not permanently blocked (see handleHover).
        UserDefaults.standard.set(false, forKey: "firstLaunch")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        })

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createNotchWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()

        // Start clipboard history capture (respects clipboardHistoryEnabled).
        Task { @MainActor in
            _ = ClipboardMonitor.shared
            ClipboardQuickPanelController.shared.startIfEnabled()
            // 电池状态监听（IOKit 沙盒内可用，无需额外权限）
            _ = BatteryStatusViewModel.shared
            // 音量管理器（CoreAudio 沙盒内可用）
            _ = VolumeManager.shared
            // 亮度/键盘背光管理器（通过 XPC Helper 访问私有框架）
            _ = BrightnessManager.shared
            _ = KeyboardBacklightManager.shared
            // 摇晃召唤悬浮暂存框（R2）：接线 onShake → FloatingNestManager；
            // 面板落巢后同步在刘海侧展开文件架，让用户立刻看到入巢结果
            FloatingNestManager.shared.start()
            FloatingNestManager.shared.onDeposit = { [weak self] screen in
                Task { @MainActor in
                    self?.handleDragEntersNotchRegion(onScreen: screen)
                }
            }
        }

        previousScreens = NSScreen.screens
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            // 类已 @MainActor，didChangeScreenParametersNotification 也在主线程投递，
            // 直接同步清理即可，无需再 dispatch 到主线程。
            cleanupWindows()
            adjustWindowPosition()
            setupDragDetectors()
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }

                if windows[uuid] == nil {
                    let viewModel = NotchViewModel(screenUUID: uuid)
                    let window = createNotchWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createNotchWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}
