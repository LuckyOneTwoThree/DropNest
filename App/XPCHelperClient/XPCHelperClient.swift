import Foundation
import Cocoa

/// XPC Helper 客户端——管理 NSXPCConnection 连接，用 withCheckedContinuation
/// 把回调式 XPC 调用包装成 async/await（不依赖 AsyncXPCConnection 第三方库）。
///
/// 安全保证：
/// - ResumeGuard 保证 continuation 恰好 resume 一次（errorHandler 与正常回调
///   存在并发双 resume 路径，双 resume 会直接崩溃）。
/// - 每次调用带超时兜底，Helper 进程挂起（非断连）时调用方不会永久 await。
final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()

    /// XPC 服务名 = Helper 的 bundle ID
    private let serviceName = "com.dropnest.app.DropNestXPCHelper"

    /// 单次 XPC 调用的超时时间
    private nonisolated static let callTimeout: Duration = .seconds(3)

    private var connection: NSXPCConnection?

    deinit {
        connection?.invalidate()
    }

    // MARK: - Resume Guard

    /// 保证 continuation 恰好 resume 一次的线程安全守卫。
    private final class ResumeGuard<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value, Never>?

        init(_ continuation: CheckedContinuation<Value, Never>) {
            self.continuation = continuation
        }

        /// 首个调用生效，后续调用被忽略（防止双 resume 崩溃）。
        func resumeOnce(with value: Value) {
            lock.lock()
            let cont = continuation
            continuation = nil
            lock.unlock()
            cont?.resume(returning: value)
        }
    }

    // MARK: - Connection Management

    @MainActor
    private func ensureConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }

        let conn = NSXPCConnection(serviceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: (any DropNestXPCHelperProtocol).self)

        conn.interruptionHandler = { [weak self, weak conn] in
            // 连接中断：显式作废旧连接，避免半存活连接被复用
            conn?.invalidate()
            Task { @MainActor in
                guard let self, self.connection === conn else { return }
                self.connection = nil
            }
        }
        conn.invalidationHandler = { [weak self, weak conn] in
            Task { @MainActor in
                guard let self, self.connection === conn else { return }
                self.connection = nil
            }
        }

        conn.resume()
        connection = conn
        return conn
    }

    /// 获取带错误处理的 proxy，连接失败时调用 errorHandler 并返回 nil。
    @MainActor
    private func getProxyWithError(errorHandler: @escaping (Error) -> Void) -> DropNestXPCHelperProtocol? {
        ensureConnection().remoteObjectProxyWithErrorHandler(errorHandler) as? DropNestXPCHelperProtocol
    }

    // MARK: - Guarded Call Helper

    /// 统一的 XPC 调用封装：错误处理、双 resume 守卫、超时兜底。
    /// - Parameters:
    ///   - fallback: 连接失败或超时时返回的兜底值
    ///   - call: 拿到 proxy 后发起调用的闭包，完成时必须调用 `reply`
    private nonisolated func withXPC<Value: Sendable>(
        fallback: Value,
        _ call: @escaping @MainActor (DropNestXPCHelperProtocol, @escaping (Value) -> Void) -> Void
    ) async -> Value {
        await withCheckedContinuation { continuation in
            let guard_ = ResumeGuard(continuation)

            // 超时兜底：Helper 挂起时避免调用方永久卡死
            Task {
                try? await Task.sleep(for: Self.callTimeout)
                guard_.resumeOnce(with: fallback)
            }

            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    guard_.resumeOnce(with: fallback)
                }
                guard let proxy else {
                    guard_.resumeOnce(with: fallback)
                    return
                }
                call(proxy) { value in
                    guard_.resumeOnce(with: value)
                }
            }
        }
    }

    // MARK: - Keyboard Brightness

    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        await withXPC(fallback: false) { proxy, reply in
            proxy.isKeyboardBrightnessAvailable { reply($0) }
        }
    }

    nonisolated func currentKeyboardBrightness() async -> Float? {
        await withXPC(fallback: nil) { proxy, reply in
            proxy.currentKeyboardBrightness { reply($0?.floatValue) }
        }
    }

    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        await withXPC(fallback: false) { proxy, reply in
            proxy.setKeyboardBrightness(value) { reply($0) }
        }
    }

    // MARK: - Screen Brightness

    /// - Parameter displayID: 目标显示器 ID。0 = 系统主显示器（向后兼容）。
    nonisolated func isScreenBrightnessAvailable(forDisplayID displayID: UInt32 = 0) async -> Bool {
        await withXPC(fallback: false) { proxy, reply in
            proxy.isScreenBrightnessAvailable(forDisplayID: displayID, with: reply)
        }
    }

    nonisolated func currentScreenBrightness(forDisplayID displayID: UInt32 = 0) async -> Float? {
        await withXPC(fallback: nil) { proxy, reply in
            proxy.currentScreenBrightness(forDisplayID: displayID, with: { reply($0?.floatValue) })
        }
    }

    nonisolated func setScreenBrightness(_ value: Float, forDisplayID displayID: UInt32 = 0) async -> Bool {
        await withXPC(fallback: false) { proxy, reply in
            proxy.setScreenBrightness(value, forDisplayID: displayID, with: reply)
        }
    }
}
