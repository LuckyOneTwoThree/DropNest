import Foundation
import AppKit
import ApplicationServices
import Defaults
import AVFoundation

private let kSystemDefinedEventType = CGEventType(rawValue: 14)!

/// 系统媒体键拦截器，通过 CGEvent tap 拦截音量/亮度按键，
/// 抑制系统原生 bezel 并改由刘海 HUD 显示。
/// 需要辅助功能权限（运行时用户授予，非 entitlement）。
@MainActor
final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    private enum NXKeyType: Int, Sendable {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case keyboardBrightnessUp = 21
        case keyboardBrightnessDown = 22
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// 定期自检 tap 健康状态，系统睡眠唤醒/显示器重连等边缘场景下 tap 可能被
    /// 静默禁用且不触发回调，导致媒体键静默失效。每 30s 检查并重新启用。
    private var healthCheckTimer: Timer?
    private let step: Float = 1.0 / 16.0
    private var audioPlayer: AVAudioPlayer?

    private init() {}

    // MARK: - Accessibility (直接使用 ApplicationServices，无 XPC)

    /// 检查辅助功能权限
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 请求辅助功能权限（弹出系统授权对话框）
    func requestAccessibilityAuthorization() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    /// 确认辅助功能权限，可选弹出提示
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool = false) async -> Bool {
        if AXIsProcessTrusted() { return true }
        if promptIfNeeded {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
            AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    // MARK: - Event Tap

    func start(promptIfNeeded: Bool = false) async {
        guard eventTap == nil else { return }

        guard Defaults[.hudReplacement] else {
            stop()
            return
        }

        let authorized = AXIsProcessTrusted()
        if !authorized {
            if promptIfNeeded {
                let granted = await ensureAccessibilityAuthorization(promptIfNeeded: true)
                guard granted else { return }
            } else {
                return
            }
        }

        let mask = CGEventMask(1 << kSystemDefinedEventType.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

                // 系统在回调耗时超阈值时会静默禁用 tap（.tapDisabledByTimeout / .tapDisabledByUserInput）。
                // 不处理则 tap 永久失效，用户感知「音量键 HUD 没了，需重启 App」——刘海类应用最高频线上投诉。
                // 立即重新启用，避免回调链中断。
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated {
                        if let tap = interceptor.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    }
                    return Unmanaged.passRetained(cgEvent)
                }

                // 回调必须同步返回事件，但实际动作（CoreAudio 读写等）同步执行易触发上述超时。
                // 改为同步完成事件判定（决定放行/吞掉），实际处理异步执行，回调本身保持微秒级。
                // 同步判定依赖的均为内存读取（NSEvent 解析 + Defaults 读取），无阻塞 I/O。
                let decision = interceptor.synchronousDecision(for: cgEvent)
                switch decision {
                case .passthrough:
                    return Unmanaged.passRetained(cgEvent)
                case .consume:
                    return nil
                case .consumeAndDispatch(let action):
                    // 吞掉原生事件后异步执行实际动作（CoreAudio 读写、HUD 显示等），
                    // 回调本身已同步返回，不会阻塞事件系统导致 tap 被禁用。
                    Task { @MainActor in interceptor.executeAsync(action) }
                    return nil
                }
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            startHealthCheck()
        }
    }

    func stop() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    /// 定期自检 tap 健康状态。系统在睡眠唤醒、显示器重连等边缘场景下可能禁用
    /// tap 但不触发 .tapDisabledByTimeout 回调，导致媒体键静默失效（需重启 App）。
    /// 每 30s 检查一次，若 tap 被禁用则重新启用。stop() 会先 invalidate 定时器
    /// 再置空 eventTap，避免定时器在停止后仍尝试重新启用已释放的 tap。
    private func startHealthCheck() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let tap = self.eventTap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthCheckTimer = timer
    }

    // MARK: - Event Handling

    /// 回调同步判定结果：决定放行还是吞掉事件，若吞掉则携带需异步执行的动作。
    private enum TapDecision: Sendable {
        case passthrough           // 放行原生事件
        case consume               // 吞掉事件，无后续动作
        case consumeAndDispatch(MediaKeyAction)
    }

    /// 回调内异步执行的实际动作（CoreAudio 读写、HUD 显示等）。
    /// 用 Sendable 枚举携带最小参数，跨 actor 传递后在 MainActor 上执行。
    private enum MediaKeyAction: Sendable {
        case optionAction(keyType: NXKeyType, command: Bool)
        case keyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool)
    }

    /// CGEvent tap 回调内同步调用（tap 挂在 main RunLoop，回调在主线程，assumeIsolated 安全）。
    /// 仅做事件解析 + 判定（NSEvent 解析 + Defaults 读取，均为内存操作，微秒级），
    /// 实际动作（CoreAudio 读写等）由调用方异步执行，避免回调超时触发 tap 被系统禁用。
    private nonisolated func synchronousDecision(for cgEvent: CGEvent) -> TapDecision {
        MainActor.assumeIsolated {
            guard cgEvent.type != .null else { return .passthrough }
            guard let nsEvent = NSEvent(cgEvent: cgEvent),
                  nsEvent.type == .systemDefined,
                  nsEvent.subtype.rawValue == 8 else {
                return .passthrough
            }

            let data1 = nsEvent.data1
            let keyCode = (data1 & 0xFFFF_0000) >> 16
            let stateByte = ((data1 & 0xFF00) >> 8)

            // 0xA = key down, 0xB = key up，只处理 key down
            guard stateByte == 0xA,
                  let keyType = NXKeyType(rawValue: keyCode) else {
                return .passthrough
            }

            let flags = nsEvent.modifierFlags
            let option = flags.contains(.option)
            let shift = flags.contains(.shift)
            let command = flags.contains(.command)

            // Option 键按下时走特殊行为（不含 shift）
            if option && !shift {
                // optionAction 只在 action != .none 时才吞掉事件
                if Defaults[.optionKeyAction] != .none {
                    return .consumeAndDispatch(.optionAction(keyType: keyType, command: command))
                }
                // action == .none：吞掉事件但不执行动作（保持原抑制原生行为语义）
                return .consume
            }

            // 检查对应能力是否启用。未启用的类别放行原生事件（透传），避免拦截后无 HUD 又抑制原生 bezel。
            guard isCapabilityEnabled(for: keyType) else { return .passthrough }

            return .consumeAndDispatch(.keyPress(keyType: keyType, option: option, shift: shift, command: command))
        }
    }

    /// 异步执行回调判定出的动作（CoreAudio 读写、HUD 显示等）。
    private func executeAsync(_ action: MediaKeyAction) {
        switch action {
        case .optionAction(let keyType, let command):
            handleOptionAction(for: keyType, command: command)
        case .keyPress(let keyType, let option, let shift, let command):
            handleKeyPress(keyType: keyType, option: option, shift: shift, command: command)
        }
    }

    /// 按键类别对应的独立功能开关是否启用。
    /// 在 hudReplacement 主开关开启的前提下，单独判断音量/亮度/键盘背光。
    private func isCapabilityEnabled(for keyType: NXKeyType) -> Bool {
        switch keyType {
        case .soundUp, .soundDown, .mute:
            return Defaults[.volumeHUDEnabled]
        case .brightnessUp, .brightnessDown:
            return Defaults[.brightnessHUDEnabled]
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            return Defaults[.keyboardBacklightHUDEnabled]
        }
    }

    /// 执行 Option 键自定义动作。仅在 optionKeyAction != .none 时被 dispatch
    /// （见 synchronousDecision），故 .none 分支不可达，保留为防御性 no-op。
    private func handleOptionAction(for keyType: NXKeyType, command: Bool) {
        let action = Defaults[.optionKeyAction]

        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
        case .showHUD:
            showHUD(for: keyType, command: command)
        case .none:
            break
        }
    }

    private func prepareAudioPlayerIfNeeded() {
        guard audioPlayer == nil else { return }

        let defaultPath = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        if FileManager.default.fileExists(atPath: defaultPath) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: defaultPath))
            } catch {
                print("⚠️ [MediaKeyInterceptor] Failed to init AVAudioPlayer: \(error.localizedDescription)")
            }
        }

        if let player = audioPlayer {
            player.volume = 1.0
            player.numberOfLoops = 0
            player.prepareToPlay()
        }
    }

    /// 系统「调节音量时播放反馈」开关。
    /// 原实现每次按键都 `persistentDomain(forName:)` 拷贝整个 NSGlobalDomain 字典（数百键），
    /// 改为 CFPreferences 单键读取 + 1 秒 TTL 缓存：连按音量键时几乎零开销，
    /// 用户在系统设置里改开关后最多 1 秒生效。
    private static var beepFeedbackCache: (value: Bool, fetchedAt: TimeInterval) = (false, -1)

    private func isBeepFeedbackEnabled() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - Self.beepFeedbackCache.fetchedAt < 1.0 {
            return Self.beepFeedbackCache.value
        }
        let raw = CFPreferencesCopyAppValue(
            "com.apple.sound.beep.feedback" as CFString,
            kCFPreferencesAnyApplication
        ) as? NSNumber
        let enabled = raw?.intValue == 1
        Self.beepFeedbackCache = (enabled, now)
        return enabled
    }

    private func playFeedbackSound() {
        guard isBeepFeedbackEnabled() else { return }

        prepareAudioPlayerIfNeeded()
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    private func handleKeyPress(keyType: NXKeyType, option: Bool, shift: Bool, command: Bool) {
        let stepDivisor: Float = (option && shift) ? 4.0 : 1.0

        switch keyType {
        case .soundUp:
            playFeedbackSound()
            VolumeManager.shared.increase(stepDivisor: stepDivisor)
        case .soundDown:
            playFeedbackSound()
            VolumeManager.shared.decrease(stepDivisor: stepDivisor)
        case .mute:
            VolumeManager.shared.toggleMuteAction()
        case .brightnessUp, .keyboardBrightnessUp:
            let delta = step / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -(step / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }

    /// 调节亮度/背光（executeAsync 已在 @MainActor 上，无需再嵌套 Task）
    private func adjustBrightness(delta: Float, keyboard: Bool) {
        if keyboard {
            KeyboardBacklightManager.shared.setRelative(delta: delta)
        } else {
            BrightnessManager.shared.setRelative(delta: delta)
        }
    }

    private func showHUD(for keyType: NXKeyType, command: Bool) {
        switch keyType {
        case .soundUp, .soundDown, .mute:
            let v = VolumeManager.shared.rawVolume
            NotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(v))
        case .brightnessUp, .brightnessDown:
            let v = BrightnessManager.shared.rawBrightness
            NotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(v))
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            let v = KeyboardBacklightManager.shared.rawBrightness
            NotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .backlight, value: CGFloat(v))
        }
    }

    private func openSystemSettings(for keyType: NXKeyType, command: Bool) {
        let urlString: String

        switch keyType {
        case .soundUp, .soundDown, .mute:
            urlString = "x-apple.systempreferences:com.apple.preference.sound"
        case .brightnessUp, .brightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.displays"
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            urlString = "x-apple.systempreferences:com.apple.preference.keyboard"
        }

        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
