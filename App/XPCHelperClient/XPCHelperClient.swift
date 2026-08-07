import Foundation
import Cocoa

/// XPC Helper 客户端——管理 NSXPCConnection 连接，用 withCheckedContinuation
/// 把回调式 XPC 调用包装成 async/await（不依赖 AsyncXPCConnection 第三方库）。
/// 使用 remoteObjectProxyWithErrorHandler 确保连接错误时 continuation 不会永久挂起。
final class XPCHelperClient: NSObject {
    nonisolated static let shared = XPCHelperClient()

    /// XPC 服务名 = Helper 的 bundle ID
    private let serviceName = "com.dropnest.app.DropNestXPCHelper"

    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?

    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }

    // MARK: - Connection Management

    @MainActor
    private func ensureConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }

        let conn = NSXPCConnection(serviceName: serviceName)
        conn.remoteObjectInterface = NSXPCInterface(with: (any DropNestXPCHelperProtocol).self)

        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
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

    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring

    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    var isMonitoring: Bool {
        return monitoringTask != nil
    }

    // MARK: - Accessibility

    nonisolated func requestAccessibilityAuthorization() {
        Task { @MainActor in
            guard let proxy = getProxyWithError(errorHandler: { _ in }) else { return }
            proxy.requestAccessibilityAuthorization()
        }
    }

    nonisolated func isAccessibilityAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    continuation.resume(returning: false)
                }
                guard let proxy else {
                    continuation.resume(returning: false)
                    return
                }
                proxy.isAccessibilityAuthorized { authorized in
                    Task { @MainActor in
                        self.notifyAuthorizationChange(authorized)
                    }
                    continuation.resume(returning: authorized)
                }
            }
        }
    }

    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    continuation.resume(returning: false)
                }
                guard let proxy else {
                    continuation.resume(returning: false)
                    return
                }
                proxy.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    Task { @MainActor in
                        self.notifyAuthorizationChange(authorized)
                    }
                    continuation.resume(returning: authorized)
                }
            }
        }
    }

    // MARK: - Keyboard Brightness

    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    continuation.resume(returning: false)
                }
                guard let proxy else {
                    continuation.resume(returning: false)
                    return
                }
                proxy.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        }
    }

    nonisolated func currentKeyboardBrightness() async -> Float? {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    continuation.resume(returning: nil)
                }
                guard let proxy else {
                    continuation.resume(returning: nil)
                    return
                }
                proxy.currentKeyboardBrightness { value in
                    continuation.resume(returning: value?.floatValue)
                }
            }
        }
    }

    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    continuation.resume(returning: false)
                }
                guard let proxy else {
                    continuation.resume(returning: false)
                    return
                }
                proxy.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }

    // MARK: - Screen Brightness

    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    continuation.resume(returning: false)
                }
                guard let proxy else {
                    continuation.resume(returning: false)
                    return
                }
                proxy.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        }
    }

    nonisolated func currentScreenBrightness() async -> Float? {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    continuation.resume(returning: nil)
                }
                guard let proxy else {
                    continuation.resume(returning: nil)
                    return
                }
                proxy.currentScreenBrightness { value in
                    continuation.resume(returning: value?.floatValue)
                }
            }
        }
    }

    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let proxy = self.getProxyWithError { _ in
                    continuation.resume(returning: false)
                }
                guard let proxy else {
                    continuation.resume(returning: false)
                    return
                }
                proxy.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
