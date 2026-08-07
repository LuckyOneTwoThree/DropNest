import XCTest

/// DropNest UI 冒烟测试。
///
/// 说明：DropNest 的主体是「刘海悬浮层 + 菜单栏图标」，没有标准 SwiftUI Settings 场景
/// （设置走自定义 `SettingsWindowController`），且状态栏图标不在 App 的 AX 树内，
/// 因此对刘海内具体 HUD 元素做精准点测较难。本套测试定位为：
///   1) 启动冒烟：App 能正常启动且不崩溃（捕获移植导致的启动崩溃回归）；
///   2) 设置页可达性断言：新增的「电池」「HUD」设置项真实存在。
///
/// 用法：在 Xcode 中 `File ▸ New ▸ Target ▸ macOS ▸ UI Testing Bundle`，
/// 名称 `DropNestUITests`，Embed in Application 选 `DropNest`，
/// 把本文件内容粘进自动生成的 `DropNestUITests.swift`，`Cmd + U` 运行。
class DropNestUITests: XCTestCase {

    /// 被测 App。bundleIdentifier 取自 project.pbxproj 的 PRODUCT_BUNDLE_IDENTIFIER。
    let app = XCUIApplication(bundleIdentifier: "theboringteam.boringnotch")

    override func setUpWithError() throws {
        continueAfterFailure = false
        // 每次从干净状态启动，避免上次运行的菜单栏/窗口残留干扰。
        app.launchArguments = ["-resetDefaultStates", "-disableMaintenanceIfAny"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// 冒烟：App 启动后进程存活，且能找到主菜单栏或任意窗口。
    func testAppLaunchesWithoutCrash() {
        let exists = app.wait(for: .running, timeout: 10)
        XCTAssertTrue(exists, "DropNest 启动失败或启动后崩溃")

        // 刘海 App 可能没有标准文档窗口；这里只断言「有可交互的 UI 实体」即可。
        let hasAnyUI = app.menuBars.count > 0 || app.windows.count > 0
        XCTAssertTrue(hasAnyUI, "启动后未检测到任何可访问 UI")
    }

    /// 尝试打开设置窗口。
    /// 由于本 App 没有标准 Settings 场景，这里用多种策略兜底，
    /// 任一成功即返回 true。若你的环境打开方式不同，请在此调整定位符。
    @discardableResult
    private func openSettings() -> Bool {
        // 策略 1：标准 Cmd+,（若后续接入了 Settings 场景）
        app.typeKey(",", modifierFlags: .command)
        if app.windows.count > 0 { return true }

        // 策略 2：菜单栏「DropNest ▸ 设置/Settings」
        for title in ["设置", "Settings", "Preferences"] {
            let item = app.menuBars.firstMatch.menuBarItems[title]
            if item.exists {
                item.click()
                if app.windows.count > 0 { return true }
            }
        }
        return app.windows.count > 0
    }

    /// 断言新增的「电池」「HUD」设置项存在于设置侧栏。
    /// 这两个项是纯 UI，不依赖硬件，是最稳的回归断言点。
    func testBatteryAndHUDSettingsExist() {
        let opened = openSettings()
        XCTAssertTrue(opened, "无法打开设置窗口——请检查 openSettings() 的定位符")

        // 侧栏使用 NavigationLink，文本即我们在 SettingsView 里写的 Label。
        let batteryRow = app.staticTexts["电池"]
        let hudRow = app.staticTexts["HUD"]

        XCTAssertTrue(
            batteryRow.waitForExistence(timeout: 5),
            "设置侧栏未找到「电池」项，可能 BatterySettings 未接入"
        )
        XCTAssertTrue(
            hudRow.waitForExistence(timeout: 5),
            "设置侧栏未找到「HUD」项，可能 HUDSettings 未接入"
        )
    }

    /// 示例：点击进入「电池」设置页，断言出现「展开态显示电池指示器」开关文案。
    /// 仅在 testBatteryAndHUDSettingsExist 通过的基础上做，验证页面可导航。
    func testBatterySettingsPageNavigates() {
        guard openSettings() else {
            XCTFail("无法打开设置窗口")
            return
        }
        let batteryRow = app.staticTexts["电池"]
        guard batteryRow.waitForExistence(timeout: 5) else {
            XCTFail("未找到电池设置项")
            return
        }
        batteryRow.click()

        let indicatorToggle = app.staticTexts["展开态显示电池指示器"]
        XCTAssertTrue(
            indicatorToggle.waitForExistence(timeout: 5),
            "进入电池设置页后未找到预期开关文案"
        )
    }
}
