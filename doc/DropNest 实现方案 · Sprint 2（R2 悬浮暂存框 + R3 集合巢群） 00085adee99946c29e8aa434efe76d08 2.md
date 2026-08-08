# DropNest 实现方案 · Sprint 2（R2 悬浮暂存框 + R3 集合巢群）

<aside>
🧭

**文档用途：**Sprint 2 逐文件实现方案（R2 摇晃召唤悬浮暂存框 + R3 集合巢群），基于 DropNest 当前代码（main @ 2026-08-08）精读产出，可直接作为桌面编码 Agent 的任务书。
**配套文档：**需求与验收定义见《DropNest 需求与功能说明 · 第一期》
**v2 修订（2026-08-08）**：按 Lucky 确认的暂存巢交互模型重写——①每个悬浮巢 = 一个集合（默认成组）；②窗口按内容数做 n×n 正方形自适应（上限默认 3×3，可配置，超出纵向滚动）；③拖拽期间系统保证存在一个浅色「空巢胚」。Part B 与 Part D 已整体重写。
**v2.1 补充（2026-08-08）**：刘海 ⇄ 桌面流转闭环——刘海 Shelf 中集合以组卡片聚合展示；Shelf 提供「一键展开/收起全部巢」；单个巢可收起回刘海；点击 Shelf 组卡片 = 该组以悬浮巢展示在桌面。

</aside>

## 目录

## 零、现状关键事实（方案的地基）🧱

以下均已在当前源码中逐行确认，方案完全建立在这些事实上：

1. **摇晃检测有现成挂点**：`observers/DragDetector.swift` 已定义 `onDragMove: PositionCallback`（拖拽期间每次移动回调全局坐标）且**当前零调用方**——摇晃检测直接挂这里，零侵入
2. **悬浮面板有现成范式**：`components/Clipboard/Views/ClipboardQuickPanel.swift` 已实现 `NSPanel(.borderless, .nonactivatingPanel)` + `level = .floating` + `showAtMouse()`（含屏幕边缘校正）+ 失焦收起——FloatingNestPanel 直接仿写
3. **集合字段零迁移成本**：`ShelfItem` 现为 `id / kind / isTemporary`；新增 `groupID: UUID?` 可选字段后，Swift 合成 Codable 对可选属性自动走 `decodeIfPresent`，**旧的 items.json 无需迁移**
4. **批量入巢有统一入口**：`ShelfStateViewModel.load(_ providers:)` 是所有拖入的唯一入口（ShelfView 与 ContentView 的 dragDetector 都走它）→ 批量自动成组只改这一处
5. **右键菜单有固定套路**：`ShelfItemViewModel.presentContextMenu` 用 title-based switch + `MenuActionTarget` → 集合操作按同一模式新增即可
6. **整体拖出有现成实现**：`ShelfItemView` 内 `DraggableClickView` 已支持多选后一次拖出多个条目（`startDragSession`/`createPasteboardItem`）→ 集合整体拖出直接复用该组装逻辑
7. **窗口体系边界清晰**：刘海窗口 = `NotchSkyLightWindow`（level `.mainMenu+3`，每屏一个，AppDelegate 管理）；悬浮窗是独立窗口族，用普通 NSPanel 即可（无需 SkyLight——悬浮窗不需要锁屏显示）

## 〇·五、暂存巢交互模型（v2 核心）🪺

<aside>
🪺

**核心模型：**每一个悬浮暂存巢 = 一个集合（groupID）。桌面可同时存在多个巢；任何拖拽期间，系统保证永远存在一个浅色「空巢胚」等待新文件。

</aside>

### 交互流（按 Lucky 确认的场景）

1. 拖起文件 A → 鼠标附近出现一个**浅色空巢胚**（虚线描边、低透明度，与有内容的巢明显区分）
2. 把 A 放进空巢胚 → 胚「孵化」为正式巢（实色、获得新 groupID G1），A 成为 G1 成员
3. 拖起文件 B → 桌面已有 G1（实色巢，进入可接收高亮态）；同时因不存在空巢，系统在拖拽起点附近再生成一个新的浅色空巢胚
4. 二选一：B 放进 G1（加入既有集合）/ B 放进空巢胚（孵化出 G2）
5. 拖拽结束而空巢胚未被使用 → 空巢胚静默消失，不留痕迹

### 默认设计决策（Lucky 可纠正）

- 空巢胚出现后**固定位置、不跟随鼠标**（跟随会干扰瞄准）
- 已收进刘海的巢在拖拽时**不自动弹出**；只有桌面上已打开的巢进入可接收高亮态
- 拖入既有巢 = 加入该巢集合（默认成组，无需修饰键）；拖入刘海总巢的条目仍是独立条目，成组语义只属于悬浮巢
- **网格自适应**：n=1 → 1×1；n=2~4 → 2×2；n=5~9 → 3×3；超过上限 → 纵向滚动；上限为设置项（默认 3）
- 窗口随网格数自适应尺寸，避免留白

### UI 风格规范（对齐 DropNest 现有视觉语言）

- 深色 `.ultraThinMaterial` 底 + 16 圆角 + 白色 10% 描边（同 ClipboardQuickPanel / ShelfView）
- 拖拽目标态：accent 色虚线描边（同 ShelfView 的 dragDetectorTargeting 表现）
- 空巢胚：整体 45% 透明度 + 灰色虚线描边 + 「拖入新建暂存巢」提示；孵化时 0.25s 弹性放大过渡
- 字体统一 system rounded

### 刘海 ⇄ 桌面流转（v2.1 补充）

- **聚合展示**：悬浮巢里成组的条目，在刘海文件架上同样以「组卡片」形式聚合展示（不拆散）
- **一键开合**：文件架顶栏新增巢群按钮——一键展开全部巢到桌面 / 一键全部收起回刘海
- **单个收起**：每个悬浮巢右上角有「收起」按钮，点击即收回刘海（集合保留在 Shelf）
- **点击展开**：点击文件架上的组卡片 → 该组以悬浮巢形式展示在桌面（位置优先取记忆位置，否则屏幕中部偏上）

### 摇晃召唤的角色变化（重要）

新模型下拖拽开始即出现巢群，摇晃不再是唯一入口。建议设置项二选一：**拖拽开始自动显示巢群**（默认开）或 **仅摇晃召唤**。摇晃手势保留，用于「不自动弹出」模式下的手动召唤。

## Part A · R3 集合巢群（先做）

<aside>
🥚

**为什么先做集合：**R2 的悬浮窗本质是「集合的桌面容器」。先把集合模型在刘海内闭环，R2 就只剩窗口工作。

</aside>

### A1 数据模型（修改 `App/components/Shelf/Models/ShelfItem.swift`）

```swift
@MainActor
struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: ShelfItemKind
    var isTemporary: Bool
    /// 所属集合；nil = 独立条目
    var groupID: UUID? = nil
    // 其余不变
}
```

- [ ]  新增 `groupID` 可选字段（旧 items.json 向后兼容）
- [ ]  `displayName` / `icon` / `identityKey` 逻辑保持不变

### A2 集合操作 API（修改 `App/components/Shelf/ViewModels/ShelfStateViewModel.swift`）

```swift
// 新增集合操作
func createGroup(from ids: Set<UUID>) -> UUID      // 给指定条目赋同一新 groupID
func dissolveGroup(_ groupID: UUID)                // 组内条目 groupID 置 nil
func items(inGroup groupID: UUID) -> [ShelfItem]   // 按组取条目

/// 渲染单元：扁平 items 折叠为 单条目/集合 序列（保序：组内首条目位置即集合位置）
enum ShelfEntry: Identifiable {
    case single(ShelfItem)
    case group(UUID, [ShelfItem])
}
var entries: [ShelfEntry] { ... }
```

- [ ]  `createGroup` / `dissolveGroup` / `items(inGroup:)` 三个方法
- [ ]  `entries` 计算属性（保序聚合）
- [ ]  `load(_ providers:)` 增加可选参数 `intoGroup groupID: UUID? = nil`：拖入既有巢时本批条目继承该巢 groupID；拖入空巢胚时由 manager 先创建新 groupID 再传入；批量拖入同一巢的条目天然共享该 groupID（v2 起成组为默认语义，不再需要独立开关）

### A3 集合卡片视图（新增 `App/components/Shelf/Views/NestGroupCardView.swift`）

- [ ]  叠层缩略图（组内前 2~3 项错位叠加）+ 数量角标 + 组名（默认「集合 N」）
- [ ]  点击 = 该组以悬浮巢形式展示在桌面（调 FloatingNestManager.toggle，v2.1）；「就地查看组内条目」移至右键菜单
- [ ]  整体拖出 = 复用 `DraggableClickView` 的 draggingItems 组装逻辑，组内全部 fileURL 写入同一 drag session

### A4 ShelfView 渲染改造（修改 `App/components/Shelf/Views/ShelfView.swift`）

- [ ]  `ForEach(tvm.items)` → `ForEach(tvm.entries)`：`.single` 渲染 `ShelfItemView`，`.group` 渲染 `NestGroupCardView`
- [ ]  顶部「N 项」计数仍按条目数（非集合数）
- [ ]  顶栏右侧新增「巢群」按钮：一键展开全部巢 / 全部收起（接 FloatingNestManager.showAll()/dockAll()；**依赖 B3，随 Part B 阶段接入**）

### A5 右键菜单（修改 `App/components/Shelf/ViewModels/ShelfItemViewModel.swift`）

- [ ]  `presentContextMenu`：多选时加「组成集合」；`item.groupID != nil` 时加「在桌面打开此集合」「就地查看」「解散集合」
- [ ]  `MenuActionTarget.handle` 按既有 title-switch 模式新增对应 case，调用 A2 的 API

## Part B · R2 悬浮暂存巢群（v2 重写）

### B1 摇晃检测器（新增 `App/observers/ShakeGestureDetector.swift`）

```swift
@MainActor
final class ShakeGestureDetector {
    static let shared = ShakeGestureDetector()
    var onShake: (CGPoint) -> Void = { _ in }

    private var samples: [(point: CGPoint, time: TimeInterval)] = []
    private var cooldownUntil: TimeInterval = 0

    /// 拖拽活跃期内由 DragDetector.onDragMove 喂入全局坐标
    func feed(_ point: CGPoint) { ... }
    func reset() { samples.removeAll() }
}
```

判定算法：仅保留最近 `window`（默认 0.8s）内的采样点；统计 X 方向符号反转次数 ≥ `reversals`（默认 3）且累计位移 ≥ `minAmplitude`（默认 8pt）→ 触发 `onShake`；触发后进入 1s 冷却。全部阈值走 Defaults（设置页可调，对应 FR-F5）。

- [ ]  新建检测器 + 判定算法 + 冷却
- [ ]  附单元测试（`DropNestTests`）：构造采样序列验证触发/不触发

### B2 悬浮暂存巢面板（新增 `App/components/Shelf/Views/FloatingNestPanel.swift`）

仿 `ClipboardQuickPanel` 的窗口配置，内容为**自适应正方形网格**：

```swift
final class FloatingNestPanel: NSPanel {
    let groupID: UUID          // 每个巢 = 一个集合
    let isGhost: Bool          // true = 浅色空巢胚
    init(groupID: UUID, isGhost: Bool) {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: FloatingNestGridView(groupID: groupID, isGhost: isGhost))
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

- [ ]  新建面板；`show(at:)` 含屏幕边缘校正（参照 ClipboardQuickPanel.showAtMouse）
- [ ]  内容视图 `FloatingNestGridView`：按 groupID 从共享 `ShelfStateViewModel` 过滤条目，渲染 n×n 正方形网格；**窗口尺寸随列数自适应**（列数 = min(ceil(√n), nestMaxGridColumns)，空胚固定 1×1）；超过上限纵向滚动
- [ ]  `onDrop` → `ShelfStateViewModel.shared.load(providers, intoGroup: groupID)`；面板的 drop `isTargeted` 用自身 @State，**禁止复用 vm.dragDetectorTargeting**
- [ ]  空巢胚样式：45% 透明度 + 灰色虚线描边 + 提示文案；被 drop 后「孵化」（切换为正式样式 + 0.25s 弹性放大）
- [ ]  生命周期：拖拽结束（mouseUp 且未发生 drop）/ Esc / 点击面板外 → 空巢胚销毁；正式巢右上角有「收起」按钮（点击即收进刘海，集合仍保留在 Shelf；可选增强：拖巢到刘海区域即收起）

### B3 巢群管理器（新增 `App/components/Shelf/FloatingNestManager.swift`）

- [ ]  多实例管理：`panels: [UUID: FloatingNestPanel]`（key = groupID）
- [ ]  拖拽开始（DragDetector 检测到内容拖拽）→ 已有巢进入可接收高亮态；若不存在空巢胚 → 在拖拽起点附近创建一个
- [ ]  空巢胚被 drop → 创建真实 groupID，胚孵化为正式巢并纳入 panels
- [ ]  拖拽结束 → 销毁未使用的空巢胚
- [ ]  **流转 API（v2.1）**：`showAll()` / `dockAll()`（刘海一键开合）、`toggle(groupID:)`（点击 Shelf 组卡片展开/收起单个巢）、`dock(groupID:)`（巢的收起按钮调用）
- [ ]  位置记忆：正式巢位置按 groupID 记录（Defaults 字典），重新展开时还原
- [ ]  与 AppDelegate 的刘海窗口体系完全隔离，不进 `NotchSpaceManager`

### B4 接线（修改 `App/DropNestApp.swift` 与 `App/observers/DragDetector.swift`）

- [ ]  DragDetector **新增两个回调**：`onContentDragStart` / `onContentDragEnd`（在 isContentDragging 状态翻转处触发）——巢群的显示/清理依赖这对钩子
- [ ]  `setupDragDetectorForScreen` 内：`detector.onDragMove = { ShakeGestureDetector.shared.feed($0) }`；`onContentDragStart` → `FloatingNestManager.shared.handleDragStart()`；`onContentDragEnd` → `handleDragEnd()` + `ShakeGestureDetector.shared.reset()`
- [ ]  `ShakeGestureDetector.onShake` → `FloatingNestManager.shared.summonGhost(at:)`（「仅摇晃召唤」模式下的手动入口）
- [ ]  `applicationWillTerminate` 中清理检测器与全部巢窗

### B5 设置键（修改 `App/models/Constants.swift`）

- [ ]  `floatingNestEnabled`（默认 true）、`nestShowOnDragStart`（默认 true；false = 仅摇晃召唤）、`shakeSensitivity`（默认 0.5）、`shakeMinAmplitude`（默认 8）、`nestMaxGridColumns`（默认 3）

### B6 设置页（修改 `App/components/Settings/SettingsView.swift`）

- [ ]  「文件架」分区新增：悬浮暂存巢开关、出现方式（拖拽开始自动 / 仅摇晃）、摇晃灵敏度滑杆、网格上限 Stepper（2~4）
- [ ]  遵循项目「功能开关全链路生效」约定（`floatingNestEnabled` 关闭时检测器与巢群全链路停用）

## Part C · 执行顺序 / 验收 / 风险 📋

### 执行顺序

1. A1 → A2 → A4 → A5（集合闭环，编译通过，刘海内自测）→ A3 卡片打磨
2. B1 → B2 → B3 → B4（摇晃 + 巢群 + 刘海⇄桌面流转）→ A4 的巢群按钮接线 → B5/B6 设置项
3. 对照《需求与功能说明》的验收标准逐项打钩

### 风险与注意

1. **摇晃判定只在拖拽活跃期有效**：`DragDetector` 仅在 `leftMouseDragged` 且 drag pasteboard 有有效内容时回调——文档与验收中需明确「拖拽中摇晃」语义
2. **drop targeting 串线**：每个巢的 isTargeted 都是自己的 @State，禁止复用刘海 vm 的 targeting 状态
3. **多屏**：DragDetector 按屏创建而管理器是全局单例——巢的位置按 point 所在屏校正
4. **空巢胚的出现时机**：依赖 DragDetector 的「内容拖拽」判定（drag pasteboard changeCount），文本/URL 拖拽同样要覆盖
5. **顺手清理**（可选）：RedundancyReview 报告的 3 个死文件——`components/Notch/NotchWindow.swift`（仍在 pbxproj 编译列表）、`helpers/Clipboard+Content.swift`、`utils/Logger.swift`

## Part D · Agent 任务提示词模板 🤖

<aside>
🤖

**用法：**一次只跑一个任务；把「上下文文件」的源码贴进 agent 会话，再贴任务正文。每个任务完成后编译验证再进下一个。

</aside>

**任务 1（A1+A2 集合模型）**

```
你在修改 macOS 应用 DropNest（SwiftUI + AppKit，沙盒，Swift 严格并发）。
上下文文件：App/components/Shelf/Models/ShelfItem.swift、App/components/Shelf/ViewModels/ShelfStateViewModel.swift、App/components/Shelf/Services/ShelfPersistenceService.swift
任务：①给 ShelfItem 新增可选字段 groupID: UUID?（默认 nil，保持对旧 items.json 的向后兼容解码）；②ShelfStateViewModel 新增 createGroup(from:)/dissolveGroup(_:)/items(inGroup:) 方法，以及 entries 计算属性（把扁平 items 折叠为 single/group 渲染单元，组内首条目位置即集合位置，保持原有顺序）；③load(_:) 末尾实现批量自动成组：dropped.count > 1 且 Defaults[.nestAutoGroupOnBatchDrop] 为 true 时，本批条目共享同一新 groupID。不改动其他既有行为。完成后编译通过。
```

**任务 2（A3+A4+A5 集合 UI）**

```jsx
上下文文件：App/components/Shelf/Views/ShelfView.swift、App/components/Shelf/Views/ShelfItemView.swift、App/components/Shelf/ViewModels/ShelfItemViewModel.swift、App/components/Shelf/ViewModels/ShelfSelectionModel.swift，以及任务 1 的产物
任务：①新建 NestGroupCardView（叠层缩略图 + 数量角标 + 组名；点击行为先留空回调，Part B 阶段接 FloatingNestManager.toggle(groupID:)）；②ShelfView 的 ForEach(tvm.items) 改为按 entries 渲染（single→ShelfItemView，group→NestGroupCardView）；③ShelfItemViewModel 的 presentContextMenu 新增「组成集合」（多选时）与「在桌面打开此集合」「就地查看」「解散集合」（item.groupID != nil 时），MenuActionTarget.handle 沿用同一 title-switch 模式接 ShelfStateViewModel 对应 API；④集合卡片支持整体拖出：参考 ShelfItemView 内 DraggableClickView 的 startDragSession/createPasteboardItem 多选拖拽实现，把组内全部 fileURL 组装进同一 drag session。
```

**任务 3（B1 摇晃检测）**

```jsx
上下文文件：App/observers/DragDetector.swift、App/models/Constants.swift
任务：①DragDetector 新增 onContentDragStart / onContentDragEnd 两个回调（在 isContentDragging 状态翻转处触发）；②新建 App/observers/ShakeGestureDetector.swift（@MainActor 单例）：feed(_ point: CGPoint) 接收拖拽期间的全局坐标采样，在最近 0.8s 时间窗内统计 X 方向符号反转次数 ≥3 且累计位移 ≥8pt 时触发 onShake(point)，触发后冷却 1s；reset() 清空采样。所有阈值读取 Defaults 键——请在 Constants.swift 新增 floatingNestEnabled（默认 true）/ nestShowOnDragStart（默认 true）/ shakeSensitivity（默认 0.5）/ shakeMinAmplitude（默认 8）/ nestMaxGridColumns（默认 3）五个键。摇晃检测为纯逻辑组件，请在 DropNestTests 附单元测试（构造采样序列验证触发与不触发两种路径）。
```

**任务 4（B2+B3+B4 暂存巢群与接线）**

```jsx
上下文文件：App/components/Clipboard/Views/ClipboardQuickPanel.swift、App/components/Clipboard/Services/ClipboardQuickPanelController.swift、App/DropNestApp.swift、App/components/Shelf/Views/ShelfView.swift、App/observers/DragDetector.swift、App/components/Shelf/ViewModels/ShelfStateViewModel.swift，以及任务 1、3 的产物
背景：DropNest 的悬浮暂存巢模型——每个悬浮巢 = 一个集合（groupID）；拖拽期间系统保证存在一个浅色「空巢胚」。
任务：①仿 ClipboardQuickPanel 新建 FloatingNestPanel（NSPanel，.borderless + .nonactivatingPanel，level .floating，isMovableByWindowBackground = true，带 groupID 与 isGhost 两个初始化参数）；内容视图 FloatingNestGridView 按 groupID 从共享 ShelfStateViewModel 过滤条目，渲染 n×n 正方形网格：列数 = min(ceil(√n), Defaults[.nestMaxGridColumns])，空胚固定 1×1，窗口尺寸随列数自适应，超出上限纵向滚动；onDrop 调 ShelfStateViewModel.shared.load(providers, intoGroup: groupID)；面板的 drop isTargeted 用自身 @State，禁止复用 NotchViewModel 的 dragDetectorTargeting。空巢胚样式：45% 透明度 + 灰色虚线描边 +「拖入新建暂存巢」提示；被 drop 后孵化为正式样式（0.25s 弹性放大）。正式巢右上角提供「收起」按钮（点击调 dock(groupID:) 收回刘海，集合保留在 Shelf）。②新建 FloatingNestManager 单例：panels: [UUID: FloatingNestPanel]；handleDragStart() 时已有巢进入高亮态、若无空巢胚则在拖拽起点附近创建；空巢胚被 drop 时创建真实 groupID 并孵化；handleDragEnd() 销毁未使用的空巢胚；summonGhost(at:) 供摇晃召唤；另需实现流转 API——showAll()/dockAll()/toggle(groupID:)/dock(groupID:)，并按 groupID 用 Defaults 字典记忆正式巢位置、重新展开时还原。生命周期注意：不要照抄 ClipboardQuickPanel 的 didResignKey 收起逻辑——拖拽期间巢不会成为 key window；空巢胚在拖拽结束/Esc/点击外部时销毁，正式巢手动关闭后集合保留在刘海 Shelf。③DropNestApp 的 setupDragDetectorForScreen 中接好 onDragMove → ShakeGestureDetector.feed、onContentDragStart/End → FloatingNestManager；applicationWillTerminate 清理。④ShelfView 顶栏右侧新增「巢群」按钮（一键展开全部 / 收起全部，接 FloatingNestManager.showAll()/dockAll()）。巢窗不进 NotchSpaceManager，与刘海窗口体系隔离。
```

**任务 5（B5/B6 设置页 + 联调）**

```jsx
上下文文件：App/models/Constants.swift、App/components/Settings/SettingsView.swift、（任务 1-4 的产物）
任务：在设置「文件架」分区新增「悬浮暂存巢」开关、「出现方式」选项（拖拽开始自动 / 仅摇晃召唤，对应 nestShowOnDragStart）、「摇晃灵敏度」滑杆、「网格列数上限」Stepper（2\~4，对应 nestMaxGridColumns）；键名与前述任务一致；遵循项目「功能开关全链路生效」约定（floatingNestEnabled 关闭时摇晃检测与巢群全链路停用）。完成后全量编译，并按《需求与功能说明》中 R2/R3 的验收标准逐项自测。
```

<aside>
🐾

方案要点回顾（v2.1）：先做集合闭环再做巢群；每个悬浮巢 = 一个集合（groupID），刘海 Shelf 以组卡片聚合展示；拖拽期间必有浅色空巢胚；网格 n×n 自适应、上限可配；刘海 ⇄ 桌面流转闭环（一键开合 / 单个收起 / 点击组卡片展开）；摇晃检测挂在 DragDetector 闲置回调上、并新增 onContentDragStart/End 钩子驱动巢群生命周期；巢窗仿写 ClipboardQuickPanel 但生命周期语义不同（不可照抄失焦收起）。执行中编译报错或手感调参问题，随时找 Bingo。

</aside>