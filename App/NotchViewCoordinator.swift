//
//  NotchViewCoordinator.swift
//  DropNest
//
//  Created by Alexander on 2024-11-20.
//  Trimmed to screen selection + media bar state only (2026-08-07).
//

import AppKit
import Combine
import Defaults
import SwiftUI

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}

/// 折叠态/展开态 Live Activity 的内容类型。
enum SneakContentType {
    case brightness
    case volume
    case backlight
    case music
    case battery
}

/// 折叠态 HUD 短闪提示状态。
struct SneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
}

/// 展开态扩展显示项（如电池横向通知）。
struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
}

@MainActor
class NotchViewCoordinator: ObservableObject {
    static let shared = NotchViewCoordinator()

    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true

    // MARK: - Expanding view (电池横向通知)
    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                let currentType = expandingView.type
                expandingViewTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard let self = self, !Task.isCancelled else { return }
                    self.toggleExpandingView(status: false, type: currentType)
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?

    /// 切换展开态扩展显示项（电池专用入口）。
    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
            }
        }
    }

    // MARK: - Sneak peek (折叠态 HUD 短闪)

    @Published var sneakPeek: SneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }

    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    /// 切换折叠态 HUD 短闪提示。
    /// 非 music 类型只在 hudReplacement 开启时才显示（不弹原生 bezel 也不弹刘海 HUD 时静默）。
    func toggleSneakPeek(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = ""
    ) {
        sneakPeekDuration = duration
        if type != .music {
            if !Defaults[.hudReplacement] {
                return
            }
        }
        Task { @MainActor in
            withAnimation(.smooth) {
                self.sneakPeek.show = status
                self.sneakPeek.type = type
                self.sneakPeek.value = value
                self.sneakPeek.icon = icon
            }
        }
    }

    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    self.toggleSneakPeek(status: false, type: .music)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }

    // MARK: - HUD replacement 订阅

    @Default(.hudReplacement) var hudReplacement
    // nonisolated(unsafe)：observer token 仅在 MainActor 的 setup 中赋值、
    // nonisolated deinit 中移除。标 nonisolated(unsafe) 允许 deinit 安全访问
    // （参照 DragDetector.swift 的 mouseDownMonitor 范式）。
    private nonisolated(unsafe) var accessibilityObserver: Any?
    private var hudReplacementCancellable: AnyCancellable?
    private var hudEnableTask: Task<Void, Never>?
    /// 辅助功能授权轮询：未授权时每 2 秒检测一次，授权后 post 通知并停止。
    /// 无此轮询时用户在系统设置授权后必须重启 App 或打开 HUD 设置页才能生效。
    private var accessibilityPollingTask: Task<Void, Never>?

    // Legacy storage for migration
    @AppStorage("preferred_screen_name") private var legacyPreferredScreenName: String?

    // New UUID-based storage
    @AppStorage("preferred_screen_uuid") var preferredScreenUUID: String? {
        didSet {
            if let uuid = preferredScreenUUID {
                selectedScreenUUID = uuid
            }
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }

    @Published var selectedScreenUUID: String = NSScreen.main?.displayUUID ?? ""

    private init() {
        // Perform migration from name-based to UUID-based storage
        if preferredScreenUUID == nil, let legacyName = legacyPreferredScreenName {
            // Try to find screen by name and migrate to UUID
            if let screen = NSScreen.screens.first(where: { $0.localizedName == legacyName }),
               let uuid = screen.displayUUID {
                preferredScreenUUID = uuid
                NSLog("✅ Migrated display preference from name '\(legacyName)' to UUID '\(uuid)'")
            } else {
                // Fallback to main screen if legacy screen not found
                preferredScreenUUID = NSScreen.main?.displayUUID
                NSLog("⚠️ Could not find display named '\(legacyName)', falling back to main screen")
            }
            // Clear legacy value after migration
            legacyPreferredScreenName = nil
        } else if preferredScreenUUID == nil {
            // No legacy value, use main screen
            preferredScreenUUID = NSScreen.main?.displayUUID
        }

        selectedScreenUUID = preferredScreenUUID ?? NSScreen.main?.displayUUID ?? ""

        // 监听辅助功能授权变化，授权后自动启动按键拦截
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if Defaults[.hudReplacement] {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
            }
        }

        // 监听 hudReplacement 设置变化
        hudReplacementCancellable = Defaults.publisher(.hudReplacement)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self = self else { return }

                    self.hudEnableTask?.cancel()
                    self.hudEnableTask = nil

                    if change.newValue {
                        self.hudEnableTask = Task { @MainActor in
                            let granted = await MediaKeyInterceptor.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
                            if Task.isCancelled { return }

                            if granted {
                                await MediaKeyInterceptor.shared.start()
                            } else {
                                // 未授权：启动轮询，授权后自动 start()
                                self.startAccessibilityPolling()
                            }
                        }
                    } else {
                        // 关闭 HUD 替换：停止拦截器与轮询
                        self.accessibilityPollingTask?.cancel()
                        self.accessibilityPollingTask = nil
                        MediaKeyInterceptor.shared.stop()
                    }
                }
            }

        // 启动时检查 HUD 替换状态
        Task { @MainActor in
            if Defaults[.hudReplacement] {
                if MediaKeyInterceptor.isAccessibilityTrusted {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                } else {
                    // 未授权时不翻回 false，启动轻量级轮询检测授权变化。
                    // macOS TCC 系统不会主动通知 App 权限状态变化，AXIsProcessTrusted()
                    // 只在调用时返回当前状态。没有轮询的话，用户在系统设置授权后
                    // 必须重启 App 或打开 HUD 设置页（那里有独立轮询）才能生效。
                    // 这里每 2 秒轮询一次，检测到授权后 post 通知，上面注册的监听器
                    // 会自动 start()，然后停止轮询。
                    self.startAccessibilityPolling()
                }
            }
        }
    }

    /// 启动辅助功能授权轮询。检测到授权后 post `accessibilityAuthorizationChanged`
    /// 通知，上面注册的监听器会自动 `MediaKeyInterceptor.shared.start()`，
    /// 然后停止轮询。hudReplacement 关闭时也停止轮询。
    private func startAccessibilityPolling() {
        accessibilityPollingTask?.cancel()
        accessibilityPollingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                guard Defaults[.hudReplacement] else { return }
                if MediaKeyInterceptor.isAccessibilityTrusted {
                    NotificationCenter.default.post(name: .accessibilityAuthorizationChanged, object: nil)
                    return
                }
            }
        }
    }

    deinit {
        if let accessibilityObserver {
            NotificationCenter.default.removeObserver(accessibilityObserver)
        }
    }
}
