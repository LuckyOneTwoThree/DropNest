# DropNest 灵动岛（电池 + HUD）构建与 GUI 测试指南

> 适用版本：DropNest 1.0（派生自 boring.notch，GPL-3.0）
> 适用范围：本次新增的「灵动岛」能力——电池状态监控 + 系统媒体键 HUD 替换（音量/亮度/键盘背光）。

---

## 1. 本次移植做了什么（速览）

| 能力 | 新增文件 | 集成点 |
| --- | --- | --- |
| 电池状态监控 | `components/Battery/BatteryView.swift`、`models/BatteryStatusViewModel.swift`、`managers/BatteryActivityManager.swift` | `NotchHeader`（展开态图标）、`ContentView`（折叠态横向通知）、`SettingsView`（电池设置页） |
| 系统 HUD 替换 | `components/HUD/{InlineHUD,OpenNotchHUD,SystemEventIndicatorModifier,MarqueeText}.swift`、`managers/{VolumeManager,BrightnessManager}.swift`、`observers/MediaKeyInterceptor.swift` | `NotchViewCoordinator`（sneakPeek / expandingView）、`ContentView`、`SettingsView`（HUD 设置页）、`DropNestApp`（启动初始化） |
| 新增配置项 | `models/Constants.swift` 中 `Defaults.Keys`：电池 4 项 + HUD 11 项 | 各开关与 UI 绑定 |

设计原则（与你之前定的口径一致）：**只做被动状态监控 / 内联状态变化，不弹原生居中 bezel，不弹交互浮层执行动作**。

---

## 2. 构建（Build）

### 2.1 方式 A：Xcode 图形界面（最稳，推荐用于 GUI 测试）

1. 用 Xcode 打开 `DropNest.xcodeproj`。
2. 首次打开会让 Xcode 自动生成 scheme（`Product ▸ Scheme ▸ DropNest`）。
3. 选目标为 `My Mac`，`Cmd + R` 运行。应用启动后以菜单栏图标 + 刘海悬浮层形式存在。
4. 想做 GUI 测试就直接 `Cmd + R` 跑起来，然后人工点测（见第 3 节清单）。

> 本项目依赖 3 个 SPM 包：`SkyLightWindow`、`LaunchAtLogin-Modern`、`Defaults`。Xcode 首次打开会自动 `Resolve Package Graph`（需联网）。

### 2.2 方式 B：命令行 `xcodebuild`

**注意（本机/CI 环境）**：本仓库在本 agent 沙盒里无法 `xcodebuild`（SPM 解析会被 `sandbox-exec` 拦截，且需要联网）。在你自己的 Mac 上正常。

**仅编译校验（不签名，验证移植代码能否通过类型检查，最快）：**

```bash
cd /path/to/DropNest
xcodebuild build \
  -project DropNest.xcodeproj \
  -scheme DropNest \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES
```

**产出可运行 App（需本机有 Apple Development 证书，或把 Team 留空走 ad-hoc）：**

```bash
xcodebuild build \
  -project DropNest.xcodeproj -scheme DropNest \
  -configuration Debug -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=你的TeamID
# 产物：~/Library/Developer/Xcode/DerivedData/DropNest-*/Build/Products/Debug/DropNest.app
```

> 排错：若报 `scheme DropNest not found`，先在 Xcode 里打开一次工程生成 scheme；或把 scheme 设为 Shared（`Product ▸ Scheme ▸ Manage Schemes` 勾选 Shared）。

### 2.3 已知会影响构建/运行的环境坑

- **`boring.notch/`、`mediaremote-adapter/` 是原始仓库残留目录**，与 `App/`（DropNest 实际源码）并存。它们不在 app target 里，不影响构建，但建议从工作区移除或 `.gitignore`，避免混淆。
- **`DropNestXPCHelper` 是独立 XPC target**：亮度/键盘背光通过它调用私有框架。GUI 测试里若测亮度，必须保证 Helper 随主 App 一起构建并随沙盒 entitlements 正确签名，否则 `BrightnessManager` 静默失败（`publish` 不触发）。
- **辅助功能权限**：HUD 替换依赖 `MediaKeyInterceptor` 的事件拦截，运行时需用户在「系统设置 ▸ 隐私与安全性 ▸ 辅助功能」中授权 DropNest。未授权时 `hudReplacement` 会被自动置回 `false`。

---

## 3. GUI 测试策略

### 3.1 手动冒烟测试清单（核心，推荐先跑）

启动 App 后逐项验证：

**电池（永久常驻 / 折叠态通知）**
- [ ] 展开刘海（悬停或手势），右上角出现电池图标 + 百分比（受 `showBatteryIndicator` / `showBatteryPercentage` 控制）。
- [ ] 插拔电源 / 开始停止充电 → 刘海折叠态短暂显示横向电池通知（电源/充电/低功耗变化时触发），约 3 秒后自动收起。
- [ ] 点击电池图标 → 弹出详情（最大容量 / 低电量模式 / 充满剩余时间），「电池设置」可跳转到系统偏好。
- [ ] 设置里关闭 `showPowerStatusNotifications` 后，电源变化不再弹横向通知。

**HUD 替换（音量/亮度/键盘背光）**
- [ ] 设置 ▸ HUD 中开启「启用 HUD 替换」，按提示授予辅助功能权限。
- [ ] 按音量键（F10~F12）→ 刘海**内联**显示音量条（默认样式在刘海下方），不再出现系统居中 bezel。
- [ ] 设置「折叠态样式 = 内联」→ 音量/亮度显示在刘海左右两侧（InlineHUD）。
- [ ] 展开态下按音量键 → 右上角胶囊状 HUD（OpenNotchHUD），可拖动进度条，可显示百分比。
- [ ] Option + 媒体键 行为可在「打开系统设置 / 显示 HUD / 无操作」间切换。

**回归**
- [ ] 音乐播放时刘海媒体条仍正常（确认移植未破坏原有 Now Playing）。
- [ ] 文件架拖入/取出正常。

### 3.2 自动化：XCUITest（UI Testing Bundle）

> 说明：本 App 主体是「刘海悬浮层 + 菜单栏图标」，没有标准 SwiftUI `Settings` 场景（走自定义 `SettingsWindowController`），且状态栏图标不在 App 的 AX 树内，因此**对刘海内具体 HUD 元素的自动化点测较难**。最务实的自动化是「启动冒烟 + 设置页可达性断言」。脚手架见 `DropNestUITests/DropNestUITests.swift`。

添加步骤（在 Xcode 里最稳，避免手改 pbxproj）：
1. `File ▸ New ▸ Target ▸ macOS ▸ UI Testing Bundle`，名称 `DropNestUITests`，Embed in Application 选 `DropNest`。
2. 把脚手架里的测试代码粘进自动生成的 `DropNestUITests.swift`。
3. 运行：`xcodebuild test -scheme DropNest -destination 'platform=macOS'`（或 Xcode 里选中测试 target 按 `Cmd + U`）。

### 3.3 自动化：Manager 单元测试（最可靠，推荐）

纯逻辑（音量/亮度 clamp、HUD 可见性门控、电池信息解析）最适合写成 XCTest，不依赖硬件与 UI。脚手架见 `DropNestTests/DropNestManagerTests.swift`。
添加步骤同上，Target 类型选 **Unit Testing Bundle**（不是 UI）。

---

## 4. 本次移植的已知问题（评审，便于回归）

1. **`MarqueeText.swift` 是死代码**：全仓库无任何引用（疑似从原项目照搬未清理）。建议删除，或真正用起来。
2. **`MediaKeyInterceptor` 的 Option 键 `none` 行为有瑕疵**：`handleOptionAction` 对 `.none` 返回 `true`（已消费），会 `return nil` 抑制系统原生 bezel 但不做任何事——即"Option+亮度且设为无操作"时，系统 bezel 被吃掉却无反馈。建议 `.none` 时改为放行事件（不抑制 bezel）。
3. **`BatteryActivityManager` 通知串行间隔 1 秒**：多事件同时发生时（如插电瞬间 powerSource/charging/lowPower 一起变），会逐条隔 1 秒处理，期间反复 `toggleExpandingView(true, .battery)` 刷新 3 秒计时器，导致电池横幅停留偏久、有抖动感。可考虑合并为一次刷新。
4. **`SystemEventIndicatorModifier` 命名与实现**：名为 `Modifier` 实为普通 `View`；`value` 用 `@Binding { didSet { DispatchQueue.main.async { sendEventBack } } }` 做回写，属于可工作的"脆弱模式"（binding 在 didSet 内被异步再次修改，存在重入）。功能 OK，但建议改为在 `DraggableProgressBar.onChange` 统一回写，去掉 didSet 回写。
5. **`BatteryView` 的 `icon` 默认 `"battery.0"`**：非标准 SF Symbol 名称，仅在底层作为占位图，渲染为空不影响，但建议改成有效名或去掉。
6. **XPC Helper 未随 GUI 测试自动校验**：亮度/背光依赖 Helper，自动化测试里若断言亮度变化，需先确认 Helper 已构建并授权；否则 `BrightnessManager` 静默失败，测试会假阴性。

---

## 5. 一页速查命令

```bash
# 仅编译校验（最快确认移植能过类型检查）
xcodebuild build -project DropNest.xcodeproj -scheme DropNest \
  -configuration Debug -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES

# 跑 UI 测试
xcodebuild test -scheme DropNest -destination 'platform=macOS'

# 跑单元测试
xcodebuild test -scheme DropNest -destination 'platform=macOS' \
  -only-testing DropNestTests
```
