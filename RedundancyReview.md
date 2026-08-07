# DropNest 代码冗余审查报告

> 对比对象：原 BoringNotch 项目（`boring.notch/boringNotch/`）
> 审查范围：当前项目源码目录 `App/`（74 个 .swift 文件）

## 结论速览

- **主干是干净的**：DropNest 已经从原 BoringNotch 大幅裁剪，日历、摄像头、首次引导、YouTube Music/Spotify/Apple Music 控制器、HelloAnimation 等原项目功能均已移除，没有"整包照搬"的冗余。
- **但残留了 3 处死代码**：要么是原项目搬过来后用不到，要么是重构后没接回编译。这 3 处建议删除。

---

## 一、死代码清单（建议删除）

### 1. `components/Notch/NotchWindow.swift`
- 定义了 `class NotchWindow: NSPanel`。
- 全项目**从未实例化**（`NotchWindow(` 0 处）、**从未被继承**（`: NotchWindow` 0 处）。
- 实际使用的窗口是 `NotchSkyLightWindow`，它**直接继承 `NSPanel`**，与 `NotchWindow` 无关。
- `DropNestApp.swift` 里的 `createNotchWindow(...)` 只是函数名，返回的是 `NotchSkyLightWindow`。
- ⚠️ 该文件**仍在 pbxproj 中（会被编译）**，属于"编译了但没人用"的死类。

### 2. `helpers/Clipboard+Content.swift`
- 只定义了两个函数：`getAttributedString(...)` 和 `isText(...)`。
- 全项目 **0 调用**（剪贴板功能实际用的是 `ClipboardMonitor` / `ClipboardHistoryStore` / `ClipboardItem` 等实现）。
- ⚠️ **不在 pbxproj 编译列表里**（属于编译遗漏的"孤儿文件"，根本没编进 App）。

### 3. `utils/Logger.swift`
- 自定义了 `Logger` / `LogCategory` / `trackLifecycle` 视图修饰器。
- 全项目 **0 调用**；项目里实际用的是 `NSLog` / 系统 `os.Logger`。
- ⚠️ **不在 pbxproj 编译列表里**（孤儿文件）。
- 留着还容易和 Swift 系统自带的 `Logger` 混淆，建议删除。

---

## 二、看似可疑、其实正常（不要误删）

| 文件 | 为什么像冗余 | 实际结论 |
|------|------|------|
| `private/CGSSpace.swift` | pbxproj 里搜不到 `CGSSpace` | `private/` 是 Xcode 16 的 **PBXFileSystemSynchronizedRootGroup（同步目录）**，自动包含全部文件；且 `NotchSpaceManager.swift` 正用它 → **正常保留** |
| `NSScreen+UUID.swift`、`URL+SecurityScoped.swift`、`NSItemProvider+LoadHelpers.swift`、`Color+AccentColor.swift`、`DataTypes+Extensions.swift`、`NSImage+Extensions.swift`、`NSMenu+AssociatedObject.swift` | 带 `+` 的文件名在脚本里一度没匹配到 | pbxproj 里均引用 4 次，**正常编译**，保留 |
| `helpers/AppIcons.swift` | 结构体 `AppIcons` 本身没被用 | 但其函数 `AppIconAsNSImage(for:)` 被 `MusicManager.swift:141` 调用 → **仍在使用**，保留 |

---

## 三、与原项目对比：已正确裁剪的部分

原 BoringNotch 有、而 DropNest 已删除（说明没有把原项目整包搬来的冗余）：
- 日历：`BoringCalendar` / `CalendarManager` / `CalendarModel` / `EventModel` / `CalendarServiceProviding`
- 摄像头：`WebcamManager`
- 首次引导：`OnboardingView`
- 音乐：`YouTube Music` 全套、`SpotifyController`、`AppleMusicController`、`HelloAnimation`

---

## 四、建议

1. **删除 3 个死代码文件**：`NotchWindow.swift`、`Clipboard+Content.swift`、`Logger.swift`（删除前建议本地编译一次确认）。
2. **顺手再扫一眼引用极少的文件**（非必须）：`AppIcons` 结构体本身、`MediaChecker`、`sizing/matters.swift` 里的 `MusicPlayerImageSizes`，确认是否真的需要。
3. 把 `Clipboard+Content.swift` 和 `Logger.swift` **加进 pbxproj 或从磁盘移除**二选一——当前它们既没被引用也不在编译列表，属于"磁盘上有、项目不认"的状态，长期会让人困惑。
