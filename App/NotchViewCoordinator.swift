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
                            }
                            // 注意：未授权时不再把 hudReplacement 翻回 false，
                            // 否则会关掉用户刚打开的开关。授权到达后由 HUDSettings
                            // 的轮询或 accessibilityAuthorizationChanged 通知自动 start()。
                        }
                    } else {
                        MediaKeyInterceptor.shared.stop()
                    }
                }
            }

        // 启动时检查 HUD 替换状态
        Task { @MainActor in
            if Defaults[.hudReplacement] {
                if MediaKeyInterceptor.isAccessibilityTrusted {
                    await MediaKeyInterceptor.shared.start(promptIfNeeded: false)
                }
                // 未授权时不翻回 false，等 accessibilityAuthorizationChanged
                // 通知到达后自动 start()
            }
        }
    }

    deinit {
        if let accessibilityObserver {
            NotificationCenter.default.removeObserver(accessibilityObserver)
        }
    }
}
