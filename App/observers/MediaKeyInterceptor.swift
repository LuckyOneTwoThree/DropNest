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

    private enum NXKeyType: Int {
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
            callback: { _, _, cgEvent, userInfo in
                guard let userInfo else { return Unmanaged.passRetained(cgEvent) }
                let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                // CGEvent tap 挂在主 RunLoop（CFRunLoopGetMain），回调在主线程触发；
                // 但 C 回调本身是 nonisolated，handleEvent 是 @MainActor 隔离方法，
                // 故用 MainActor.assumeIsolated 同步切入 MainActor（回调必须同步返回事件）。
                return MainActor.assumeIsolated {
                    interceptor.handleEvent(cgEvent)
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
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - Event Handling

    private func handleEvent(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard cgEvent.type != .null else {
            return Unmanaged.passRetained(cgEvent)
        }
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passRetained(cgEvent)
        }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let stateByte = ((data1 & 0xFF00) >> 8)

        // 0xA = key down, 0xB = key up，只处理 key down
        guard stateByte == 0xA,
              let keyType = NXKeyType(rawValue: keyCode) else {
            return Unmanaged.passRetained(cgEvent)
        }

        let flags = nsEvent.modifierFlags
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)

        // Option 键按下时走特殊行为（不含 shift）
        if option && !shift {
            if handleOptionAction(for: keyType, command: command) {
                return nil
            }
        }

        // 检查对应能力是否启用。未启用的类别放行原生事件（透传），避免拦截后无 HUD 又抑制原生 bezel。
        if !isCapabilityEnabled(for: keyType) {
            return Unmanaged.passRetained(cgEvent)
        }

        handleKeyPress(keyType: keyType, option: option, shift: shift, command: command)
        return nil
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

    private func handleOptionAction(for keyType: NXKeyType, command: Bool) -> Bool {
        let action = Defaults[.optionKeyAction]

        switch action {
        case .openSettings:
            openSystemSettings(for: keyType, command: command)
            return true
        case .showHUD:
            showHUD(for: keyType, command: command)
            return true
        case .none:
            return true
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

    private func playFeedbackSound() {
        guard let feedback = UserDefaults.standard.persistentDomain(forName: "NSGlobalDomain")?["com.apple.sound.beep.feedback"] as? Int,
              feedback == 1 else { return }

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
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.increase(stepDivisor: stepDivisor)
            }
        case .soundDown:
            Task { @MainActor in
                self.playFeedbackSound()
                VolumeManager.shared.decrease(stepDivisor: stepDivisor)
            }
        case .mute:
            Task { @MainActor in
                VolumeManager.shared.toggleMuteAction()
            }
        case .brightnessUp, .keyboardBrightnessUp:
            let delta = step / stepDivisor
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessUp || command)
        case .brightnessDown, .keyboardBrightnessDown:
            let delta = -(step / stepDivisor)
            adjustBrightness(delta: delta, keyboard: keyType == .keyboardBrightnessDown || command)
        }
    }

    /// 调节亮度/背光
    private func adjustBrightness(delta: Float, keyboard: Bool) {
        Task { @MainActor in
            if keyboard {
                KeyboardBacklightManager.shared.setRelative(delta: delta)
            } else {
                BrightnessManager.shared.setRelative(delta: delta)
            }
        }
    }

    private func showHUD(for keyType: NXKeyType, command: Bool) {
        Task { @MainActor in
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
