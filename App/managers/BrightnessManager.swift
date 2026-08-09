import AppKit

/// 显示器亮度管理器，通过 XPC Helper 调用 DisplayServices/IOKit 私有 API 读写屏幕亮度。
@MainActor
final class BrightnessManager: ObservableObject {
    static let shared = BrightnessManager()

    @Published private(set) var rawBrightness: Float = 0
    @Published private(set) var animatedBrightness: Float = 0
    @Published private(set) var lastChangeAt: Date = .distantPast

    private let visibleDuration: TimeInterval = 1.2
    private let client = XPCHelperClient.shared

    private init() { refresh() }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    func refresh() {
        Task { @MainActor in
            if let current = await client.currentScreenBrightness() {
                publish(brightness: current, touchDate: false)
            }
        }
    }

    @MainActor func setRelative(delta: Float) {
        Task { @MainActor in
            let starting = await client.currentScreenBrightness() ?? rawBrightness
            let target = max(0, min(1, starting + delta))
            let ok = await client.setScreenBrightness(target)
            if ok {
                publish(brightness: target, touchDate: true)
                NotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(target))
            } else {
                refresh()
                NotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(rawBrightness))
            }
        }
    }

    func setAbsolute(value: Float) {
        let clamped = max(0, min(1, value))
        Task { @MainActor in
            let ok = await client.setScreenBrightness(clamped)
            if ok {
                publish(brightness: clamped, touchDate: true)
            } else {
                refresh()
            }
        }
    }

    private func publish(brightness: Float, touchDate: Bool) {
        // 类已 @MainActor，所有调用方均在 MainActor 上，无需再 dispatch 到主线程。
        if rawBrightness != brightness || touchDate {
            if touchDate { lastChangeAt = Date() }
            rawBrightness = brightness
            animatedBrightness = brightness
        }
    }
}

// MARK: - Keyboard Backlight Controller

/// 键盘背光管理器，通过 XPC Helper 调用 CoreBrightness 私有框架读写键盘背光。
@MainActor
final class KeyboardBacklightManager: ObservableObject {
    static let shared = KeyboardBacklightManager()

    @Published private(set) var rawBrightness: Float = 0
    @Published private(set) var lastChangeAt: Date = .distantPast

    private let visibleDuration: TimeInterval = 1.2
    private let client = XPCHelperClient.shared

    private init() { refresh() }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    func refresh() {
        Task {
            if let current = await client.currentKeyboardBrightness() {
                publish(brightness: current, touchDate: false)
            }
        }
    }

    func setRelative(delta: Float) {
        Task {
            let starting = await client.currentKeyboardBrightness() ?? rawBrightness
            let target = max(0, min(1, starting + delta))
            let ok = await client.setKeyboardBrightness(target)
            if ok {
                publish(brightness: target, touchDate: true)
                NotchViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .backlight,
                    value: CGFloat(target)
                )
            } else {
                refresh()
                NotchViewCoordinator.shared.toggleSneakPeek(
                    status: true,
                    type: .backlight,
                    value: CGFloat(rawBrightness)
                )
            }
        }
    }

    func setAbsolute(value: Float) {
        let clamped = max(0, min(1, value))
        Task {
            let ok = await client.setKeyboardBrightness(clamped)
            if ok {
                publish(brightness: clamped, touchDate: true)
            } else {
                refresh()
            }
        }
    }

    private func publish(brightness: Float, touchDate: Bool) {
        // 类已 @MainActor 隔离，无需 DispatchQueue.main.async 跳帧
        if rawBrightness != brightness || touchDate {
            if touchDate { lastChangeAt = Date() }
            rawBrightness = brightness
        }
    }
}
