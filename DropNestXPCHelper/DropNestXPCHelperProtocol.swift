import Foundation

/// XPC Helper 协议——主 App 与非沙盒 XPC 服务之间的通信契约。
/// 所有方法用 @objc 修饰 + reply 回调（NSXPCConnection 异步模式）。
@objc protocol DropNestXPCHelperProtocol {
    // MARK: - 键盘背光 (CoreBrightness 私有框架)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)

    // MARK: - 屏幕亮度 (DisplayServices 私有框架 + IOKit 回退)
    /// - Parameter displayID: 目标显示器 ID（CGDirectDisplayID）。主 App 传入当前选中屏幕的 displayID，
    ///   使多显示器环境下亮度调节作用于用户实际操作的屏幕，而非硬编码的主显示器。
    ///   displayID=0 时回退到 CGMainDisplayID()（保持向后兼容）。
    func isScreenBrightnessAvailable(forDisplayID displayID: UInt32, with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(forDisplayID displayID: UInt32, with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, forDisplayID displayID: UInt32, with reply: @escaping (Bool) -> Void)
}
