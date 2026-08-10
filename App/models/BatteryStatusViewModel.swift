import Cocoa
import Foundation
import IOKit.ps
import SwiftUI

/// 电池状态 ViewModel，把 BatteryActivityManager 的事件流转成 SwiftUI 可绑定的 @Published 属性，
/// 并在重要变化（电源/充电/低功耗）时触发刘海折叠态横向电池通知。
@MainActor
class BatteryStatusViewModel: ObservableObject {

    @ObservedObject var coordinator = NotchViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: UUID?

    /// 低电量通知阈值（百分比）。电量降到该值及以下且未插电时触发一次折叠态通知。
    private let lowBatteryThreshold: Float = 20
    /// 是否已处于低电量通知状态，避免在低电量区间内每次变化都重复触发。
    private var hasNotifiedLowBattery = false

    static let shared = BatteryStatusViewModel()

    private init() {
        setupPowerStatus()
        setupMonitor()
    }

    /// 初始化时拉取一次电池信息
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// 注册 BatteryActivityManager 观察者
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    /// 处理电池事件，更新对应属性
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? String(localized: "Power Connected", locale: LanguageManager.shared.currentLocale) : String(localized: "Power Disconnected", locale: LanguageManager.shared.currentLocale)
                self.notifyImportanChangeStatus()
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            withAnimation {
                self.levelBattery = level
            }
            checkLowBatteryNotification(level: level)

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            self.notifyImportanChangeStatus()
            withAnimation {
                self.isInLowPowerMode = isEnabled
                let state = self.isInLowPowerMode ? String(localized: "On", locale: LanguageManager.shared.currentLocale) : String(localized: "Off", locale: LanguageManager.shared.currentLocale)
                self.statusText = String(localized: "Low Power Mode: \(state)", locale: LanguageManager.shared.currentLocale)
            }

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            self.notifyImportanChangeStatus()
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                    ? String(localized: "Charging", locale: LanguageManager.shared.currentLocale)
                    : (self.levelBattery < self.maxCapacity ? String(localized: "Not Charging", locale: LanguageManager.shared.currentLocale) : String(localized: "Fully Charged", locale: LanguageManager.shared.currentLocale))
            }

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            print("⚠️ Error: \(description)")
        }
    }

    /// 用 BatteryInfo 更新所有属性
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? String(localized: "Power Connected", locale: LanguageManager.shared.currentLocale) : String(localized: "Power Disconnected", locale: LanguageManager.shared.currentLocale)
        }
    }

    /// 低电量（≤阈值）且未插电时触发一次折叠态通知；电量恢复或插电后重置标记，允许下次再触发。
    /// 仅在「正常 → 低电」的状态转换时通知，避免在低电量区间内每次电量变化都重复打扰。
    private func checkLowBatteryNotification(level: Float) {
        let isLow = level <= lowBatteryThreshold && !isPluggedIn && !isCharging
        if isLow && !hasNotifiedLowBattery {
            hasNotifiedLowBattery = true
            withAnimation {
                self.statusText = String(localized: "Low Battery \(Int(level))%", locale: LanguageManager.shared.currentLocale)
            }
            notifyImportanChangeStatus()
        } else if !isLow {
            hasNotifiedLowBattery = false
        }
    }

    /// 重要变化时触发刘海折叠态电池通知
    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    /// BatteryStatusViewModel 为单例（shared），deinit 不会触发；移除观察者依赖
    /// @MainActor 隔离的 managerBattery.removeObserver(byId:)，无法在 nonisolated
    /// deinit 中调用，单例生命周期内观察者始终有效，无需手动移除。

}
