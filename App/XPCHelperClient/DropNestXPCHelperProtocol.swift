import Foundation

/// XPC Helper 协议副本——供主 App 编译用（与 XPC target 中的协议定义保持一致）。
@objc protocol DropNestXPCHelperProtocol {
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    func isScreenBrightnessAvailable(forDisplayID displayID: UInt32, with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(forDisplayID displayID: UInt32, with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, forDisplayID displayID: UInt32, with reply: @escaping (Bool) -> Void)
}
