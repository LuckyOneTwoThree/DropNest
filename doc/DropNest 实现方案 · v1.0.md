# DropNest 实现方案 · v1.0

<aside>
🧭

**文档用途**：DropNest v1.0 完整实现方案，基于 main @ e957a1d 源码精读产出，覆盖 8 大需求模块的架构设计、关键文件、核心算法与工程优化。
**配套文档**：需求与验收定义见《DropNest 需求与功能说明 · v1.0》
**取代说明**：本文件取代《DropNest 实现方案 · Sprint 2》（仅覆盖悬浮巢 + 集合两模块的局部方案）。
**版本基线**：v1.0 ｜ 2026-08-08 ｜ main @ e957a1d

</aside>

## 目录

## 零、总体架构 🏛️

### 0.1 分层架构

```
┌─────────────────────────────────────────────────────────┐
│                    表现层（SwiftUI）                     │
│  ContentView · ShelfView · FloatingNestPanel ·          │
│  ClipboardHistoryView · InlineHUD · BatteryView         │
├─────────────────────────────────────────────────────────┤
│                  ViewModel 层（@MainActor）              │
│  NotchViewModel · ShelfStateViewModel ·                 │
│  ClipboardHistoryViewModel · BatteryStatusViewModel     │
├─────────────────────────────────────────────────────────┤
│                   Service 层（可跨 actor）               │
│  ShelfPersistenceService · ThumbnailService ·           │
│  ClipboardHistoryStore · ImageProcessingService ·       │
│  ShelfItemResolutionCache · TemporaryFileStorageService │
├─────────────────────────────────────────────────────────┤
│                  Manager 层（@MainActor 单例）           │
│  VolumeManager · BrightnessManager · MusicManager ·     │
│  BatteryActivityManager · FloatingNestManager ·         │
│  NotchSpaceManager · NotchViewCoordinator               │
├─────────────────────────────────────────────────────────┤
│               观察者 / 拦截器（@MainActor）               │
│  DragDetector · MediaKeyInterceptor ·                   │
│  ShakeGestureDetector · ClipboardMonitor               │
├─────────────────────────────────────────────────────────┤
│                    XPC Helper（非沙盒）                  │
│  DropNestXPCHelper · XPCHelperClient                    │
├─────────────────────────────────────────────────────────┤
│              窗口层（SkyLightWindow + NSPanel）          │
│  NotchSkyLightWindow · FloatingNestPanel ·              │
│  ClipboardQuickPanel · SettingsWindowController         │
└─────────────────────────────────────────────────────────┘
```

### 0.2 窗口体系

| 窗口类型 | 基类 | level | 用途 | 管理者 |
|---------|------|-------|------|--------|
| 刘海窗口 | NotchSkyLightWindow | `.mainMenu + 3` | 刘海主体（每屏一个） | AppDelegate |
| 悬浮巢 | NSPanel（non-activating + floating） | `.floating` | 桌面暂存巢 | FloatingNestManager |
| 剪贴板快速面板 | NSPanel（borderless, non-activating） | `.floating` | `⌃⌥V` 快速面板 | ClipboardQuickPanelController |
| 设置窗口 | NSWindow | `.normal` | 设置界面 | SettingsWindowController |

**隔离原则**：悬浮巢窗口族与刘海窗口体系完全隔离，不进 `NotchSpaceManager`，由 `FloatingNestManager` 独立管理。

### 0.3 目录结构

```
DropNest/
├── App/                              # 主 App 源码
│   ├── DropNestApp.swift             # @main 入口 + AppDelegate
│   ├── ContentView.swift             # 刘海整体布局
│   ├── NotchViewCoordinator.swift    # 刘海视图协调器
│   ├── DropNest.entitlements         # 沙盒权限声明
│   ├── components/
│   │   ├── Notch/                    # 刘海窗口、形状、频谱、头部
│   │   ├── Shelf/                    # 文件架 + 悬浮巢群
│   │   │   ├── Models/               # ShelfItem、Bookmark、ShelfItemResolutionCache
│   │   │   ├── Services/             # 拖放/持久化/缩略图/图片处理/临时文件
│   │   │   ├── ViewModels/           # ShelfStateViewModel/ShelfItemViewModel/ShelfSelectionModel
│   │   │   ├── Views/                # ShelfView/FloatingNestPanel/NestGroupCardView/ShelfItemView
│   │   │   └── FloatingNestManager.swift
│   │   ├── Clipboard/                # 剪贴板历史（Models/Services/ViewModels/Views）
│   │   ├── HUD/                      # 系统 HUD（InlineHUD/OpenNotchHUD/SystemEventIndicator）
│   │   ├── Battery/                  # 电池指示视图
│   │   └── Settings/                 # 8 分页设置窗口
│   ├── managers/                     # Volume/Brightness/Battery/Music/NotchSpace
│   ├── MediaControllers/             # NowPlaying 抽象层
│   ├── observers/                    # DragDetector/MediaKeyInterceptor/ShakeGestureDetector
│   ├── XPCHelperClient/              # XPC 客户端（async/await 封装）
│   ├── models/                       # Constants、NotchViewModel、BatteryStatusViewModel
│   └── sizing/ extensions/ helpers/  # 工具
├── DropNestXPCHelper/                # XPC Helper target（非沙盒）
│   ├── DropNestXPCHelper.swift       # 亮度/背光/辅助功能授权
│   └── DropNestXPCHelper.entitlements
├── mediaremote-adapter/              # 媒体监听子模块
├── Configuration/dmg/                # DMG 打包配置
├── .github/workflows/                # GitHub Actions CI
├── DropNestTests/                    # 单元测试
└── DropNest.xcodeproj/
```

## Part A · R1 刘海媒体条（Now Playing）🎵

### A1 架构

```
mediaremote-adapter（perl 子进程）
        ↓ JSON Lines
NowPlayingController（@MainActor）
        ↓ @Published PlaybackState
MusicManager（@MainActor 单例）
        ↓ @Published
ContentView（频谱 + 封面 + 曲目信息）
```

### A2 关键文件

| 文件 | 职责 |
|------|------|
| `App/MediaControllers/NowPlayingController.swift` | 对接 mediaremote-adapter，解析 JSON Lines |
| `App/managers/MusicManager.swift` | 媒体状态管理，驱动刘海展开/收起 |
| `App/components/Notch/AudioSpectrumView.swift` | 动态频谱可视化 |
| `mediaremote-adapter/` | 系统级 Now Playing 接口的 perl 适配层 |

### A3 工程要点

- **NowPlayingController** 用 `URL.fileURL(path:)` + `Process.terminationHandler` + `withCheckedThrowingContinuation` 启动 perl 子进程，避免 `waitUntilExit` 阻塞
- **PlaybackState** 为 `@MainActor` 的 `@Published` 属性，deinit 不调用 `destroy()`（AnyCancellable 自动取消）
- **AudioSpectrumView** 的 Timer 加入 `.common` mode，deinit 中 `invalidate()`
- **readData()** 用 `withTaskCancellationHandler` 包裹，close/cancel 路径上 resume 空 Data，避免 continuation 泄漏

## Part B · R2 文件架（Shelf）📦

### B1 架构

```
DragDetector（拖拽检测）
        ↓ providers
ShelfDropService（拖放解析）
        ↓ ShelfItem[]
ShelfStateViewModel（@MainActor 单例）
        ↓ @Published items
        ├─→ ShelfView（刘海内）
        └─→ FloatingNestPanel（桌面悬浮巢，按 groupID 过滤）

ShelfPersistenceService（800ms 防抖 + 后台写盘）
ShelfItemResolutionCache（书签解析/展示名/图标缓存，30s TTL）
ThumbnailService（actor，NSCache 100条/256MB）
```

### B2 关键文件

| 文件 | 职责 |
|------|------|
| `App/components/Shelf/Models/ShelfItem.swift` | 数据模型 + ShelfItemResolutionCache |
| `App/components/Shelf/Models/Bookmark.swift` | security-scoped bookmark 封装 |
| `App/components/Shelf/Services/ShelfPersistenceService.swift` | 持久化（防抖 + 后台写盘） |
| `App/components/Shelf/Services/ThumbnailService.swift` | 缩略图缓存（actor + NSCache） |
| `App/components/Shelf/Services/ImageProcessingService.swift` | 图片处理（抠图/格式转换/PDF） |
| `App/components/Shelf/Services/TemporaryFileStorageService.swift` | 临时文件管理（terminationHandler + continuation） |
| `App/components/Shelf/ViewModels/ShelfStateViewModel.swift` | 状态管理（@MainActor 单例） |
| `App/components/Shelf/ViewModels/ShelfItemViewModel.swift` | 单条目 VM（copiedURLs 超时释放） |
| `App/components/Shelf/Views/ShelfView.swift` | 刘海内文件架视图（LazyHStack） |

### B3 工程要点

#### B3.1 书签解析缓存（30s TTL）

```swift
final class ShelfItemResolutionCache {
    static let shared = ShelfItemResolutionCache()
    private struct Timed<T> { let value: T; let storedAt: Date }
    private let ttl: TimeInterval = 30
    private var contexts: [Data: Timed<(url: URL, bookmark: Data)>] = [:]
    private var displayNames: [Data: Timed<String>] = [:]
    private var icons: [String: Timed<NSImage>] = [:]
    private let lock = NSLock()
    // 查询时检查 TTL，过期则返回 nil 触发重新解析
}
```

**设计要点**：
- 非 @MainActor，用 NSLock 保护，可跨 actor 调用
- 30s TTL 确保文件改名/移动后自动重新解析
- 容量上限 1000，超限整体清空（代价仅重新解析一轮）
- key 用 bookmark data 本身，书签刷新后 key 变化自动失效

#### B3.2 持久化防抖

```swift
// ShelfPersistenceService
func save(_ items: [ShelfItem]) {
    saveTask?.cancel()
    saveTask = Task.detached(priority: .utility) {
        try? await Task.sleep(nanoseconds: 800_000_000) // 800ms 防抖
        guard !Task.isCancelled else { return }
        let data = try JSONEncoder().encode(items) // 后台编码
        try? data.write(to: url, options: .atomic) // 后台写盘
    }
}
```

#### B3.3 批量操作后台化

```swift
// ShelfStateViewModel
func deleteGroup(_ groupID: UUID) {
    let toRemove = items.filter { $0.groupID == groupID }
    items.removeAll { $0.groupID == groupID } // UI 立即更新
    Task.detached(priority: .utility) {        // 文件清理后台执行
        for item in toRemove { item.cleanupStoredData() }
    }
}
```

#### B3.4 ShelfItem 去 MainActor 化

- `ShelfItem` 本体非隔离（Codable/Equatable 可在后台线程使用）
- `fileURL` / `cleanupStoredData` 解耦 ViewModel 单例，可跨 actor 调用
- `icon` 仍标 `@MainActor`（NSWorkspace.shared.icon 属 AppKit 主线程惯例）
- `displayName` / `identityKey` 通过 `ShelfItemResolutionCache` 缓存，避免主线程书签解析

## Part C · R3 悬浮暂存巢群（Floating Nest）🪺

### C1 架构

```
DragDetector.onContentDragStart/End
        ↓
FloatingNestManager（@MainActor 单例）
        ├─→ panels: [UUID: FloatingNestPanel]
        ├─→ showAll() / dockAll() / toggle(groupID:) / dock(groupID:)
        └─→ hatchGhost()（空巢胚孵化，completion 回调）

FloatingNestPanel（NSPanel + NSHostingView）
        ├─→ FloatingNestRootView（SwiftUI）
        │     ├─→ NestGroupCardView（集合卡片）
        │     └─→ LazyVGrid（网格自适应）
        └─→ NestDragSourceView（拖出基类）
```

### C2 关键文件

| 文件 | 职责 |
|------|------|
| `App/components/Shelf/FloatingNestManager.swift` | 悬浮巢群管理器 |
| `App/components/Shelf/Views/FloatingNestPanel.swift` | 悬浮巢窗口 + SwiftUI 根视图 |
| `App/components/Shelf/Views/NestGroupCardView.swift` | 集合卡片视图 |
| `App/observers/ShakeGestureDetector.swift` | 摇晃检测器 |
| `App/observers/DragDetector.swift` | 拖拽检测（驱动巢群生命周期） |

### C3 工程要点

#### C3.1 空巢胚生命周期

```
DragDetector.onContentDragStart
    → FloatingNestManager.showAll()（已有巢进入高亮态）
    → hatchGhost()（生成空巢胚 ghostPanel）
    
拖入空巢胚
    → onDrop 先暂存 providers
    → onHatch 触发（创建真实 groupID）
    → hatchGhost 读取 pendingDropProviders
    → ghostPanel 转移为正式 panel
    
DragDetector.onContentDragEnd
    → handleDragEnd 延迟 100ms 执行（确保 hatchGhost 完成 ghostPanel 转移）
    → 未使用的空巢胚自动销毁
```

#### C3.2 网格自适应

```swift
// FloatingNestRootView
let columns = min(ceil(Double(items.count).squareRoot()), nestMaxGridColumns)
// n=1 → 1列；n=2~4 → 2列；n=5~9 → 3列（上限可配置）
// 窗口尺寸随列数自适应
```

#### C3.3 三层手势分离

| 手势区域 | 触发动作 | 实现 |
|---------|---------|------|
| 标题栏抓手区 | 窗口移动 | NSPanel `isMovableByWindowBackground` |
| 网格空白区 | 整体拖出 | NestDragSourceView `resolveDragMembers()` 返回全部 |
| 单个条目图标 | 单条目拖出 | NestDragSourceView `resolveDragMembers()` 返回单个 |

**基类设计**：`NestDragSourceView` 封装 NSDraggingSource 协议，子类仅提供 `resolveDragMembers()` 方法，消除 90% 代码重复。

#### C3.4 窗口动画

```swift
// 展开动画：0.3s easeOut 弹性放大淡入
// 收起动画：0.25s easeIn 缩小淡出
// 关键：completionHandler 中强引用 self 确保动画完成
// 关键：先 removeValue 再 hide()，避免 ARC 提前释放 panel
```

#### C3.5 拖出语义

```
copyOnDrag = true（默认）→ 复制副本，原路径不变
copyOnDrag = false       → 移动原文件，原路径改变
```

## Part D · R4 集合（巢群）管理 🪺

### D1 数据模型

```swift
struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ShelfItemKind
    var isTemporary: Bool
    var groupID: UUID?  // nil = 独立条目；同 UUID = 同集合
}
```

**向后兼容**：`groupID` 为可选字段，Swift 合成 Codable 对可选属性走 `decodeIfPresent`，旧 items.json 无需迁移。

### D2 渲染单元

```swift
enum ShelfEntry: Identifiable, Equatable {
    case single(ShelfItem)
    case group(UUID, [ShelfItem])
}

// ShelfStateViewModel.entries 计算属性
// 将扁平 items 折叠为渲染单元序列，保序：组内首条目位置即集合位置
```

### D3 关键 API

```swift
// ShelfStateViewModel
func createGroup(from ids: Set<UUID>) -> UUID     // 赋新 groupID
func dissolveGroup(_ groupID: UUID)               // groupID 置 nil
func deleteGroup(_ groupID: UUID)                 // 移除组内所有条目
func items(inGroup groupID: UUID) -> [ShelfItem]  // 按组取条目
func remove(_ items: [ShelfItem])                 // 批量移除（单次 items 变更 + 单个清理 task）
```

### D4 空组清理

所有导致组变空的操作统一调用 `FloatingNestManager.closePanel(for:)`：

| 操作 | 位置 |
|------|------|
| 解散集合 | `dissolveGroup` |
| 清空文件架 | `clearAll` → `dockAll()` |
| 删除集合 | `deleteGroup`（由 FloatingNestManager.deleteGroup 调用） |
| 单条目移除 | `remove` 检查组是否变空 |
| 孵化失败 | `hatchGhost` 回滚 |

### D5 刘海 ⇄ 桌面流转

```
刘海 → 桌面：点击 Shelf 组卡片 → FloatingNestManager.toggle(groupID:)
桌面 → 刘海：悬浮巢「收起」按钮 → FloatingNestManager.dock(groupID:)
一键展开：ShelfView 顶栏按钮 → FloatingNestManager.showAll()
一键收回：ShelfView 顶栏按钮 → FloatingNestManager.dockAll()
```

位置记忆：`Defaults[nestPositions]` 按 groupID 存储，恢复时取记忆值。

## Part E · R5 剪贴板历史（Clipboard）📋

### E1 架构

```
ClipboardMonitor（500ms 轮询 changeCount）
        ↓ NSPasteboard
ClipboardFilter（隐私过滤）
        ↓ 过滤后
ClipboardHistoryStore（@MainActor 单例）
        ├─→ items.json（元数据）
        ├─→ blobs/（图片二进制）
        └─→ @Published items
                ↓
        ClipboardHistoryViewModel
                ↓ displayedItems（稳定分区排序）
                ↓
        ClipboardHistoryView（刘海内标签页）
        ClipboardQuickPanel（⌃⌥V 快速面板）
```

### E2 关键文件

| 文件 | 职责 |
|------|------|
| `App/components/Clipboard/Models/ClipboardItem.swift` | 数据模型 + SHA256 去重 |
| `App/components/Clipboard/Services/ClipboardMonitor.swift` | 500ms 轮询 + 来源识别 |
| `App/components/Clipboard/Services/ClipboardFilter.swift` | 隐蔽类型跳过 + 忽略 App + 大小上限 |
| `App/components/Clipboard/Services/ClipboardHistoryStore.swift` | 持久化 + 容量/时效淘汰 + blob 管理 |
| `App/components/Clipboard/Services/ClipboardQuickPanelController.swift` | Carbon 热键 + CGEvent 自动粘贴 |
| `App/components/Clipboard/ViewModels/ClipboardHistoryViewModel.swift` | 排序 + 过滤 + 缓存 |
| `App/components/Clipboard/Views/ClipboardHistoryView.swift` | 刘海内列表视图 |
| `App/components/Clipboard/Views/ClipboardItemView.swift` | 单条目视图（异步加载图片） |
| `App/components/Clipboard/Views/ClipboardQuickPanel.swift` | 快速面板（NSPanel） |

### E3 工程要点

#### E3.1 多类型 payload

```swift
struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    var contentHash: String  // SHA256 去重键
    var text: String?
    var rtfData: String?     // base64（<4KB 内联）或 blob 文件名
    var htmlData: String?    // 同上
    var imagePath: String?   // blobs/ 下文件名
    var fileURLs: [URL]?
    var pinned: Bool
    var firstCopiedAt: Date
    var lastCopiedAt: Date
}
```

#### E3.2 后台化

- 图片 TIFF→PNG 转换、SHA256 哈希、blob 写盘全部后台执行
- items.json 编码 + atomic write 后台执行
- 状态更新回主线程

#### E3.3 过期清理

```swift
// ClipboardHistoryStore
private var pruneTimer: Timer?

init() {
    // 每 10 分钟扫描过期条目
    pruneTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.pruneExpired() }
    }
    RunLoop.main.add(pruneTimer!, forMode: .common)
}
```

#### E3.4 小体积内联

```swift
// RTF/HTML < 4KB 内联到 JSON，避免碎片 blob 文件
let blobThreshold = 4096
if data.count < blobThreshold {
    item.rtfData = data.base64EncodedString() // 内联
} else {
    let path = writeBlob(data)               // 落盘
    item.rtfData = path                       // 存文件名
}
```

#### E3.5 热键

- `⌃⌥V`：Carbon `RegisterEventHotKey`（无需权限）
- 自动粘贴 `⌘V`：CGEvent 注入（需辅助功能权限，可选）

#### E3.6 视图优化

- `ClipboardHistoryView` 缓存排序结果，避免每次 body 重算
- `ClipboardItemView` 异步加载图片/appIcons 到 `@State`
- `displayedItems` 用稳定分区排序，避免不稳定排序导致闪烁

## Part F · R6 系统 HUD 替换 🎛️

### F1 架构

```
系统媒体键事件
        ↓
CGEvent Tap（MediaKeyInterceptor）
        ├─→ 同步判定（synchronousDecision）
        │     ├─→ .passthrough → 放行
        │     ├─→ .consume → 吞掉
        │     └─→ .consumeAndDispatch(action) → 吞掉 + 异步执行
        ↓
executeAsync（@MainActor）
        ├─→ VolumeManager（CoreAudio）
        ├─→ BrightnessManager（XPC Helper）
        ├─→ KeyboardBacklightManager（XPC Helper）
        └─→ NotchViewCoordinator.toggleSneakPeek（HUD 显示）
```

### F2 关键文件

| 文件 | 职责 |
|------|------|
| `App/observers/MediaKeyInterceptor.swift` | CGEvent Tap + 同步判定 + 异步执行 |
| `App/managers/VolumeManager.swift` | CoreAudio 音量控制 |
| `App/managers/BrightnessManager.swift` | XPC 屏幕亮度 |
| `App/managers/KeyboardBacklightManager.swift` | XPC 键盘背光 |
| `App/components/HUD/InlineHUD.swift` | 折叠态内联 HUD |
| `App/components/HUD/OpenNotchHUD.swift` | 展开态 HUD |
| `App/components/HUD/SystemEventIndicator.swift` | 事件指示器 |

### F3 工程要点

#### F3.1 回调异步化

```swift
// CGEvent Tap 回调
private nonisolated func synchronousDecision(for cgEvent: CGEvent) -> TapDecision {
    MainActor.assumeIsolated {
        // 仅做 NSEvent 解析 + Defaults 读取（内存操作，微秒级）
        // 返回 .passthrough / .consume / .consumeAndDispatch(action)
    }
}

// 实际动作异步执行
Task { @MainActor in interceptor.executeAsync(action) }
```

**设计依据**：回调必须同步返回事件，但实际动作（CoreAudio 读写等）同步执行易触发超时。改为同步判定 + 异步执行，回调保持微秒级。

#### F3.2 Tap 自恢复 + 健康检查

```swift
// 回调中检测 tap 被禁用
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    CGEvent.tapEnable(tap: tap, enable: true) // 立即重新启用
    return Unmanaged.passRetained(cgEvent)
}

// 30s 健康检查
private var healthCheckTimer: Timer?
// 每 30s 检查 tapIsEnabled，睡眠唤醒等边缘场景下自动恢复
```

#### F3.3 三类独立开关

```swift
private func isCapabilityEnabled(for keyType: NXKeyType) -> Bool {
    switch keyType {
    case .soundUp, .soundDown, .mute:
        return Defaults[.volumeHUDEnabled]
    case .brightnessUp, .brightnessDown:
        return Defaults[.brightnessHUDEnabled]
    case .keyboardBrightnessUp, .keyboardBrightnessDown:
        return Defaults[.keyboardBacklightHUDEnabled]
    }
}
```

未启用的类别放行原生事件，避免拦截后无 HUD 又抑制原生 bezel。

#### F3.4 音频设备切换跟随

```swift
// VolumeManager
private var cachedDeviceID: AudioObjectID?

private func systemOutputDeviceID() -> AudioObjectID {
    if let cached = cachedDeviceID { return cached }
    // ... 获取 deviceID
    cachedDeviceID = defaultDeviceID
    return defaultDeviceID
}

// 监听默认输出设备变更
// handleDefaultDeviceChange: 注销旧监听 → 注册新监听
// listener 块用 [weak self] 避免循环引用
```

#### F3.5 事件保序

```swift
// 移除 handleKeyPress/adjustBrightness/showHUD 中冗余嵌套 Task { @MainActor in }
// executeAsync 已在 MainActor，每次按键动作原子完成
// 连续快速按键不会乱序
```

#### F3.6 反馈音缓存

```swift
// 系统「调节音量时播放反馈」开关
// 原实现每次按键拷贝整个 NSGlobalDomain 字典
// 改为 CFPreferencesCopyAppValue 单键读取 + 1s TTL 缓存
private static var beepFeedbackCache: (value: Bool, fetchedAt: TimeInterval) = (false, -1)
```

## Part G · R7 电池指示 🔋

### G1 架构

```
IOKit.ps RunLoopSource（事件驱动）
        ↓
BatteryActivityManager（@MainActor 单例）
        ↓ @Published
BatteryStatusViewModel（@MainActor）
        ↓
BatteryView（刘海内电量条）
```

### G2 关键文件

| 文件 | 职责 |
|------|------|
| `App/managers/BatteryActivityManager.swift` | IOKit 事件监听 + observer 管理 |
| `App/models/BatteryStatusViewModel.swift` | 电池状态 + 低电量通知 |
| `App/components/Battery/BatteryView.swift` | 电量条视图 |

### G3 工程要点

- **事件驱动**：IOKit.ps RunLoopSource，无轮询
- **observer 管理**：用 `[UUID: closure]` 字典，避免 `remove(at:)` 导致索引位移
- **低电量通知**：20% 阈值，一次性触发（标志位保护）
- **@MainActor**：BatteryActivityManager observer 闭包标注 `@MainActor`

## Part H · R8 XPC Helper 架构 🔧

### H1 架构

```
主 App（沙盒）
        ↓ NSXPCConnection
XPCHelperClient（async/await 封装）
        ↓
DropNestXPCHelper（非沙盒，独立进程）
        ├─→ DisplayServices + IOKit（屏幕亮度）
        ├─→ CoreBrightness 私有框架（键盘背光）
        └─→ AXIsProcessTrusted（辅助功能授权）
```

### H2 关键文件

| 文件 | 职责 |
|------|------|
| `App/XPCHelperClient/XPCHelperClient.swift` | XPC 客户端（async/await 封装） |
| `App/XPCHelperClient/DropNestXPCHelperProtocol.swift` | XPC 协议定义 |
| `DropNestXPCHelper/DropNestXPCHelper.swift` | XPC Helper 实现 |
| `DropNestXPCHelper/DropNestXPCHelperProtocol.swift` | XPC 协议（Helper 侧） |
| `DropNestXPCHelper/main.swift` | XPC Helper 入口 |
| `DropNestXPCHelper/DropNestXPCHelper.entitlements` | Helper 权限声明（沙盒禁用） |

### H3 工程要点

#### H3.1 异步通信

```swift
// XPCHelperClient
func getBrightness() async -> Float {
    await withCheckedContinuation { continuation in
        connection.remoteObjectProxyWithErrorHandler { error in
            continuation.resume(returning: -1) // 错误兜底
        } performing: { proxy in
            proxy.getBrightness { value in
                continuation.resume(returning: value)
            }
        }
    }
}
```

#### H3.2 IOKit 资源释放

```swift
// DropNestXPCHelper
func isScreenBrightnessAvailable() -> Bool {
    let service = IOServiceGetMatchingService(...)
    defer { IOObjectRelease(service) } // 显式释放
    return service != 0
}
```

#### H3.3 Entitlements

| Target | 沙盒 | 关键 entitlements |
|--------|------|-------------------|
| DropNest（主 App） | ✅ 启用 | App Sandbox, 文件访问（书签） |
| DropNestXPCHelper | ❌ 禁用 | 无（需调用私有 API） |

## Part I · 性能与稳定性工程 ⚙️

### I1 主线程零文件 IO

所有 FileManager 操作在后台线程执行：

| 操作 | 位置 | 策略 |
|------|------|------|
| 删除集合 | `deleteGroup` | `Task.detached` |
| 清空文件架 | `clearAll` | `Task.detached` |
| 单条目移除 | `remove` | `Task.detached` |
| 批量移除 | `remove([ShelfItem])` | 单个 `Task.detached` |
| 书签解析 | `ShelfItemResolutionCache` | 非 @MainActor + NSLock |
| 剪贴板图片入库 | `ClipboardHistoryStore` | 后台执行 |
| 持久化写盘 | `ShelfPersistenceService` | 800ms 防抖 + 后台 |

### I2 缓存机制

| 缓存 | 容量 | TTL | 线程安全 |
|------|------|-----|---------|
| ShelfItemResolutionCache | 1000 条 | 30s | NSLock |
| ThumbnailService NSCache | 100 条 / 256MB | mtime 变化失效 | actor |
| mtimeMemo | 500 条 | 1s | actor |
| beepFeedbackCache | 1 条 | 1s | @MainActor 静态 |

### I3 严格并发

```swift
// SWIFT_STRICT_CONCURRENCY = targeted

// @MainActor 隔离的 7 个 UI 状态类：
// - NotchViewModel
// - BatteryStatusViewModel
// - MusicManager
// - BrightnessManager
// - BatteryActivityManager
// - MediaKeyInterceptor
// - AppDelegate

// 模型层去 MainActor 化：
// - ShelfItem（非隔离，可后台编解码）
// - ShelfItemResolutionCache（非隔离，NSLock 保护）
// - ImageProcessingService（非 @MainActor，Vision/CIContext 后台解码）
```

### I4 CGEvent Tap 健壮性

- 超时自恢复：回调检测 `.tapDisabledByTimeout` 立即重新启用
- 用户输入自恢复：回调检测 `.tapDisabledByUserInput` 立即重新启用
- 30s 健康检查：定时器检查 `tapIsEnabled`，失败时重新启用
- 回调异步化：同步判定 + 异步执行，回调微秒级

### I5 XPC 错误处理

- `remoteObjectProxyWithErrorHandler` 避免永久挂起
- 错误时返回默认值（如亮度 -1）
- interruption handler 中 invalidate 旧连接

### I6 视图性能

- `ShelfView` 主网格用 `LazyHStack`（非 `HStack`），避免一次渲染全部条目
- `ClipboardHistoryView` 缓存排序结果
- `ClipboardItemView` 异步加载图片/appIcons 到 `@State`
- `ShelfItemView` / `NestGroupCardView` / `ShelfView` / `FloatingNestPanel` 遵循 `Equatable` + `.equatable()` 修饰符
- `FloatingNestRootView` 减少调用 `items(inGroup:)`（从 3 次降到 1 次）

## Part J · 持续集成与发布 🚀

### J1 GitHub Actions

文件：`.github/workflows/build.yml`

**触发条件**：
- push tag `v*` → 构建并创建 GitHub Release
- 手动触发（Actions → Run workflow）→ 仅构建，上传 artifact

**构建流程**：
1. Checkout 代码
2. `xcodebuild` Release 构建（ad-hoc 签名 `CODE_SIGN_IDENTITY="-"`）
3. 定位 `DropNest.app`
4. 安装 dmgbuild（hash-pinned）
5. 调用 `create_dmg.sh` 生成 DMG
6. 上传 artifact（30 天保留）
7. tag 触发时创建 GitHub Release

**签名说明**：CI 无开发者账号，使用 ad-hoc 签名。用户下载后需 `xattr -d com.apple.quarantine` 去隔离属性。正式签名+公证版本需本地开发者账号构建。

### J2 测试

| 测试文件 | 覆盖范围 |
|---------|---------|
| `DropNestTests/ClipboardItemTests.swift` | 剪贴板数据模型 |
| `DropNestTests/DropNestManagerTests.swift` | 管理器基础逻辑 |
| `DropNestTests/ShakeGestureDetectorTests.swift` | 摇晃检测 |
| `DropNestTests/ShelfItemCodableTests.swift` | ShelfItem 编解码（含 groupID 向后兼容） |
| `DropNestTests/ShelfStateViewModelTests.swift` | 文件架状态管理 |

<aside>
🐾

**文档维护**：本文档为 v1.0 交付基线。任何后续架构变更请先更新本文档再动手，保持单一事实来源。

</aside>
