import XCTest
import Defaults

/// DropNest Manager / 逻辑单元测试。
///
/// 适用：不依赖具体硬件与 UI 的纯逻辑（音量 clamp、HUD 可见性门控、电池 ViewModel 初始化）。
/// 亮度/键盘背光依赖 XPC Helper（私有框架），在测试环境多半不可用，相关断言已做跳过保护。
///
/// 用法：Xcode 中 `File ▸ New ▸ Target ▸ macOS ▸ Unit Testing Bundle`，
/// 名称 `DropNestTests`，Target to be tested 选 `DropNest`，
/// 把本文件内容粘进生成的测试文件，`Cmd + U`（或 `xcodebuild test -only-testing DropNestTests`）运行。
///
/// 注意：用 `@testable import DropNest` 访问 internal 类；若模块名不是 DropNest，请改为实际 PRODUCT_MODULE_NAME。
@testable import DropNest

final class DropNestManagerTests: XCTestCase {

    // MARK: - VolumeManager（软件降级路径，headless 也能测）

    /// setAbsolute 必须落在 [0,1]，越界被夹紧。
    func testVolumeSetAbsoluteClampsToUnitRange() {
        let m = VolumeManager.shared

        m.setAbsolute(2.0)   // 超过 1
        let above = m.rawVolume
        m.setAbsolute(-0.5)  // 低于 0
        let below = m.rawVolume

        // publish 走主线程异步，给一点时间
        let exp = expectation(description: "volume publish")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertLessThanOrEqual(above, 1.0)
            XCTAssertGreaterThanOrEqual(below, 0.0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    /// increase / decrease 步进受 stepDivisor 影响，结果仍在 [0,1]。
    func testVolumeIncreaseDecreaseStaysInRange() {
        let m = VolumeManager.shared
        m.setAbsolute(0.5)

        m.increase(stepDivisor: 1.0)
        m.decrease(stepDivisor: 1.0)

        let exp = expectation(description: "volume step")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertGreaterThanOrEqual(m.rawVolume, 0.0)
            XCTAssertLessThanOrEqual(m.rawVolume, 1.0)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - NotchViewCoordinator（HUD 可见性门控，纯逻辑可测）

    /// hudReplacement 关闭时，非 music 类型的 sneakPeek 应被抑制（不弹原生 bezel 时静默）。
    @MainActor
    func testSneakPeekSuppressedWhenHUDReplacementOff() async {
        Defaults[.hudReplacement] = false
        let coordinator = NotchViewCoordinator.shared

        coordinator.toggleSneakPeek(status: true, type: .volume, value: 0.5)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(coordinator.sneakPeek.show,
                       "hudReplacement 关闭时，音量 sneakPeek 不应显示")
    }

    /// hudReplacement 开启时，音量 sneakPeek 应显示。
    @MainActor
    func testSneakPeekShownWhenHUDReplacementOn() async {
        Defaults[.hudReplacement] = true
        let coordinator = NotchViewCoordinator.shared

        coordinator.toggleSneakPeek(status: true, type: .volume, value: 0.5)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(coordinator.sneakPeek.show,
                      "hudReplacement 开启时，音量 sneakPeek 应显示")
        XCTAssertEqual(coordinator.sneakPeek.type, .volume)

        // 复位，避免影响其他测试
        coordinator.toggleSneakPeek(status: false, type: .volume)
        Defaults[.hudReplacement] = false
    }

    /// 展开态电池横向通知（expandingView）可正常开关。
    @MainActor
    func testExpandingViewBatteryToggle() async {
        let coordinator = NotchViewCoordinator.shared
        coordinator.toggleExpandingView(status: true, type: .battery)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(coordinator.expandingView.show)
        XCTAssertEqual(coordinator.expandingView.type, .battery)

        coordinator.toggleExpandingView(status: false, type: .battery)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(coordinator.expandingView.show)
    }

    // MARK: - BatteryStatusViewModel（初始化冒烟）

    /// 单例初始化不应崩溃，且能读出初始电量字段（无需插拔事件）。
    func testBatteryViewModelInitializes() {
        let vm = BatteryStatusViewModel.shared
        // 仅断言对象存在且字段可读；具体值依赖真实硬件。
        XCTAssertNotNil(vm)
        // levelBattery 等初始为 0 属正常（首次拉取前）。
        XCTAssertTrue(vm.levelBattery >= 0)
    }
}
