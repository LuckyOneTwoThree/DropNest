import Foundation

/// XPC Helper 协议——主 App 与非沙盒 XPC 服务之间的通信契约。
/// 所有方法用 @objc 修饰 + reply 回调（NSXPCConnection 异步模式）。
@objc protocol DropNestXPCHelperProtocol {
    // MARK: - 辅助功能
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)

    // MARK: - 键盘背光 (CoreBrightness 私有框架)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)

    // MARK: - 屏幕亮度 (DisplayServices 私有框架 + IOKit 回退)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
}
