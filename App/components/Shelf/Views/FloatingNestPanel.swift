//
//  FloatingNestPanel.swift
//  DropNest
//
//  悬浮暂存巢面板（v2.2 重写）：
//  - 空巢胚：紧凑胶囊式落点指示器（非全尺寸空面板），优雅提示"拖入新建"
//  - 正式巢：iOS 风格精炼卡片，n×n 自适应网格
//  - 动画：spring 弹性，匹配刘海 .bouncy(duration: 0.4) 风格
//  与刘海窗口体系完全隔离，不进 NotchSpaceManager。
//

import AppKit
import SwiftUI
import Defaults

// MARK: - 动画

extension Animation {
    /// 暂存巢弹性动画，匹配刘海 .bouncy(duration: 0.4)
    static var nestSpring: Animation {
        if #available(macOS 14.0, *) {
            .spring(.bouncy(duration: 0.4))
        } else {
            .timingCurve(0.16, 1, 0.3, 1, duration: 0.4)
        }
    }
    /// 轻柔弹性（尺寸变化用）
    static var nestSmooth: Animation {
        .spring(response: 0.35, dampingFraction: 0.82)
    }
}

// MARK: - Panel

final class FloatingNestPanel: NSPanel {
    /// 巢对应的集合 ID。空巢胚用临时 UUID 占位，孵化时由 manager 赋予真实 groupID
    var groupID: UUID
    private(set) var isGhost: Bool

    private var ghostPanel: NSPanel?
    // nonisolated(unsafe)：keyMonitor 仅在 MainActor 的 startKeyMonitor/stopKeyMonitor 中读写、
    // nonisolated deinit 中 removeMonitor。标 nonisolated(unsafe) 允许 deinit 安全访问
    // （参照 DragDetector.swift 的 mouseDownMonitor 范式）。
    private nonisolated(unsafe) var keyMonitor: Any?

    /// 正式巢的收起回调（收进刘海，集合保留在 Shelf）
    var onDock: ((UUID) -> Void)?
    /// 正式巢的删除回调（删除集合全部条目并关闭巢）
    var onDelete: ((UUID) -> Void)?
    /// 空巢胚被 drop 后的孵化回调
    var onHatch: ((FloatingNestPanel) -> Void)?

    init(groupID: UUID, isGhost: Bool) {
        self.groupID = groupID
        self.isGhost = isGhost

        let initialSize: CGSize = isGhost ? Self.ghostSize : NestGridLayout.size(for: 0)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        appearance = NSAppearance(named: .darkAqua) // 强制深色外观，避免浅色下材质渲染异常
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // 手势区域分离：关闭背景拖动，窗口移动限定在标题栏区域（NestTitleBarDragView 调 performDrag）
        isMovableByWindowBackground = false
        isMovable = false

        rebuildContentView()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - 尺寸常量

    /// 空巢胚胶囊尺寸（含阴影余量，复用 NestGridLayout.shadowInset）
    private static let ghostSize: CGSize = CGSize(width: 172 + NestGridLayout.shadowInset * 2, height: 44 + NestGridLayout.shadowInset * 2)

    // MARK: - 显示/隐藏

    @MainActor func show(at point: CGPoint) {
        let frame = self.frame
        var origin = NSPoint(x: point.x + 14, y: point.y - frame.height - 14)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
            origin.x = min(max(origin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
            origin.y = min(max(origin.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
        if !isGhost { makeKey() }
        startKeyMonitor()
    }

    /// 在已设好的 frame 位置入场（用于记忆位置路径）
    @MainActor func showAtCurrentFrame() {
        orderFrontRegardless()
        makeKey()
        startKeyMonitor()
    }

    @MainActor func hide() {
        stopKeyMonitor()
        orderOut(nil)
    }

    /// 断开 SwiftUI 订阅：清除 contentView 后 NSHostingView 释放，
    /// FloatingNestRootView 的 @StateObject 订阅随之销毁。
    /// 用于面板即将被丢弃的场景（closePanel/closeAllPanels），
    /// 避免 items 变更时已隐藏的面板仍触发无用 SwiftUI 重绘。
    /// 面板不会再显示时调用；dockAll 等保留面板的场景不调用。
    @MainActor func detachContentView() {
        contentView = nil
    }

    // MARK: - 孵化

    /// 空巢胚孵化为正式巢：切换内容 + 弹性放大
    @MainActor func hatch(to groupID: UUID) {
        self.groupID = groupID
        isGhost = false
        isMovable = true

        // 先调整窗口尺寸（避免内容被 ghost 尺寸裁剪），以中心为锚点弹性放大
        let target = NestGridLayout.size(for: 0)
        let oldFrame = frame
        var newFrame = oldFrame
        newFrame.size = target
        newFrame.origin.x = oldFrame.midX - target.width / 2
        newFrame.origin.y = oldFrame.midY - target.height / 2
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            setFrame(newFrame, display: true)
        }
        invalidateShadow()

        // 尺寸调整后再重建内容（SwiftUI 内部 onAppear 做 scale+fade 弹入动画）
        rebuildContentView()
    }

    /// 条目数变化后调整窗口尺寸（平滑动画）
    @MainActor func adjustSize(for count: Int) {
        let target = NestGridLayout.size(for: count)
        let oldFrame = frame
        var newFrame = oldFrame
        newFrame.size = target
        // 保持左上角不动（更自然）
        newFrame.origin.y = oldFrame.maxY - target.height
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            setFrame(newFrame, display: true)
        }
        invalidateShadow()
    }

    private func rebuildContentView() {
        contentView = NSHostingView(
            rootView: FloatingNestRootView(
                groupID: groupID,
                isGhost: isGhost,
                onDock: { [weak self] in
                    guard let self else { return }
                    self.onDock?(self.groupID)
                },
                onDelete: { [weak self] in
                    guard let self else { return }
                    self.onDelete?(self.groupID)
                },
                onHatch: { [weak self] in
                    guard let self else { return }
                    self.onHatch?(self)
                }
            )
        )
    }

    // MARK: - Keyboard (Esc)

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent monitor handler 是 @Sendable 闭包（nonisolated），但回调在主线程 RunLoop 派发。
            // MainActor.assumeIsolated 向编译器声明隔离，零运行时开销。
            MainActor.assumeIsolated {
                guard let self, self.isKeyWindow else { return event }
                if event.keyCode == 53 { // esc
                    self.hide()
                    return nil
                }
                return event
            }
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

// MARK: - SwiftUI 内容视图

private struct FloatingNestRootView: View {
    let groupID: UUID
    let isGhost: Bool
    var onDock: (() -> Void)?
    var onDelete: (() -> Void)?
    var onHatch: (() -> Void)?

    @StateObject private var tvm = ShelfStateViewModel.shared
    @State private var isDropTargeted = false
    @State private var appear = false
    /// 整体拖出预览图（堆叠缩略图 + 数量角标），预渲染缓存
    @State private var cachedDragPreview: NSImage?

    var body: some View {
        let members = tvm.items(inGroup: groupID)
        return Group {
            if isGhost {
                ghostIndicator
            } else {
                nestCard(members: members)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 让内容居中，区域外透明
        .onAppear {
            withAnimation(.nestSpring) { appear = true }
        }
        .task(id: members.map(\.id)) {
            // 预渲染整体拖出预览图，避免拖拽瞬间卡顿
            guard !members.isEmpty else { return }
            cachedDragPreview = renderNestDragPreview(members: members)
        }
    }

    /// 渲染堆叠缩略图 + 数量角标的拖拽预览图
    @MainActor
    private func renderNestDragPreview(members: [ShelfItem]) -> NSImage {
        let content = NestDragPreviewView(
            thumbnails: members.prefix(3).map { $0.icon },
            count: members.count
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.nsImage ?? members.first?.icon ?? NSImage()
    }

    // MARK: - 空巢胚（紧凑胶囊式落点指示器）

    private var ghostIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.8))
            Text("松手新建暂存巢")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(isDropTargeted ? 1.0 : 0.7)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        }
        .overlay {
            Capsule()
                .strokeBorder(
                    isDropTargeted ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.15),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [4])
                )
        }
        .scaleEffect(appear ? 1.0 : 0.85)
        .opacity(appear ? 1.0 : 0)
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isDropTargeted) { providers in
            guard Defaults[.boringShelf] else { return false }
            // 先暂存 providers，再延迟到下一个 runloop 触发孵化
            // 避免在 onDrop 回调内同步重建 contentView 导致 drop 会话状态错乱
            FloatingNestManager.shared.pendingDropProviders = providers
            // .onDrop 闭包已是 @MainActor；Task { @MainActor in } 保持"延迟到下一个 runloop"
            // 语义，同时避免 DispatchQueue.main.async 把闭包变为 nonisolated 上下文触发 actor 隔离警告。
            Task { @MainActor in
                onHatch?()
            }
            return true
        }
    }

    // MARK: - 正式巢

    private func nestCard(members: [ShelfItem]) -> some View {
        VStack(spacing: 0) {
            // 精炼顶栏：tray 图标+数量 = 整体拖出抓手，按钮区 = 收起/删除，其余空白 = 移动窗口
            HStack(spacing: 6) {
                // 整体拖出抓手（带浅色背景提示，面积足够大）
                HStack(spacing: 5) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                    Text("\(members.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("项")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor.opacity(0.1))
                )
                .overlay(
                    NestGroupDragHandler( // 抓手区 = 整体拖出
                        members: members,
                        previewImage: cachedDragPreview
                    )
                )
                .help("拖动此处以整体拖出全部文件")
                .contentShape(Rectangle())

                Spacer()
                Button(action: { onDock?() }) {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("收起（集合保留在刘海）")
                Button(action: { onDelete?() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.7))
                        .padding(3)
                        .background(Circle().fill(Color.red.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("删除集合")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(NestTitleBarDragHandler()) // 标题栏其余空白 = 移动窗口

            // 网格内容：cell overlay 单个拖出，网格空白区可右键触发整体拖出菜单
            if members.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("载入中…")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(height: 40)
                .padding(.bottom, 14)
            } else {
                NestGridContent(members: members)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                    .background(NestGroupDragHandler( // 网格区整体拖出（background 在 cell 下方，cell 优先命中，空白区穿透）
                        members: members,
                        previewImage: cachedDragPreview
                    ))
            }
        }
        // 阴影直接挂在背景的圆角矩形形状上 → 投影必然圆角，且 VStack 仍按内容尺寸排版
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.20), radius: 14, x: 0, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.1),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        .scaleEffect(appear ? 1.0 : 0.88)
        .opacity(appear ? 1.0 : 0)
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isDropTargeted) { providers in
            guard Defaults[.boringShelf] else { return false }
            tvm.load(providers, intoGroup: groupID)
            return true
        }
    }
}

// MARK: - n×n 正方形网格

private struct NestGridContent: View {
    let members: [ShelfItem]

    private var columns: Int { NestGridLayout.columnCount(for: members.count) }

    var body: some View {
        // 不用 ScrollView：避免其 frame 拦截空白区 hit testing。
        // 暂存巢条目少，无需滚动；LazyVGrid 空白区天然穿透到 background 整体拖出
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(64), spacing: 6), count: columns),
            spacing: 6
        ) {
            ForEach(members) { item in
                NestCell(item: item)
                    .equatable()
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 充满整个卡片内容区，最大化整体拖出空白区
    }
}

// MARK: - 网格 cell（精炼 iOS 风格 + 单个拖出）

private struct NestCell: View {
    let item: ShelfItem
    // 缓存 icon 和 displayName，避免 body 路径每次重估都触发同步磁盘 IO
    //（ShelfItemResolutionCache 未命中时 item.icon→NSWorkspace.icon、
    //  item.displayName→Data(contentsOf:) 均为主线程阻塞）。
    // .task 只在 appear / item.id 变化时执行一次，不随父视图重估重复触发。
    @State private var icon: NSImage?
    @State private var displayName: String = ""

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: icon ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            Text(displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 60)
        }
        .overlay(NestCellDragHandler(item: item)) // 单个条目拖出
        // 用 item 整体（含 kind）作为缓存键，而非仅 item.id：
        // bookmark 刷新时 item.id 不变但 kind 变化，用 item.id 会导致 .task 不重新执行，
        // @State icon/displayName 永久停留在旧值（文件改名/移动后显示过期）。
        .task(id: item) {
            icon = item.icon
            displayName = item.displayName
        }
    }
}

// MARK: - NestCell Equatable（item 不变时跳过 body 重估）

extension NestCell: Equatable {
    static func == (lhs: NestCell, rhs: NestCell) -> Bool {
        // item 不变时 @State icon/displayName 通过 .task(id: item.id) 保持同步，
        // 无需重估 body。item 变化时重绘。
        lhs.item == rhs.item
    }
}

// MARK: - 网格布局计算

enum NestGridLayout {
    /// 列数：min(ceil(√n), maxColumns)
    static func columnCount(for count: Int) -> Int {
        guard count > 0 else { return 1 }
        let root = Int(ceil(Double(count).squareRoot()))
        return min(root, Defaults[.nestMaxGridColumns])
    }

    /// 行数
    static func rowCount(for count: Int) -> Int {
        guard count > 0 else { return 1 }
        return Int(ceil(Double(count) / Double(columnCount(for: count))))
    }

    /// 窗口尺寸随列数自适应
    /// 格子 64pt + 间距 6pt + padding（外12+内4）×2=32pt + 顶栏 44pt + 底部 18pt + 阴影余量 2×shadowInset
    static let shadowInset: CGFloat = 12
    static func size(for count: Int) -> CGSize {
        let cols = columnCount(for: count)
        let rows = rowCount(for: count)
        let cell: CGFloat = 64
        let gap: CGFloat = 6
        let padding: CGFloat = 32 // 外层 12 + 内层 4，左右各 16
        let header: CGFloat = 44
        let footer: CGFloat = 18  // 外层 14 + 内层 4
        let width = CGFloat(cols) * cell + CGFloat(max(cols - 1, 0)) * gap + padding + shadowInset * 2
        let height = CGFloat(rows) * cell + CGFloat(max(rows - 1, 0)) * gap + header + footer + shadowInset * 2
        return CGSize(width: max(width, 140 + shadowInset * 2), height: max(height, 100 + shadowInset * 2))
    }
}

// MARK: - 暂存巢拖拽预览（堆叠缩略图 + 数量角标）

private struct NestDragPreviewView: View {
    let thumbnails: [NSImage]
    let count: Int

    var body: some View {
        ZStack {
            ForEach(Array(thumbnails.prefix(3).enumerated()), id: \.offset) { index, image in
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    .offset(
                        x: CGFloat(index) * 5 - CGFloat(min(thumbnails.count, 3) - 1) * 2.5,
                        y: -CGFloat(index) * 3
                    )
                    .zIndex(Double(index))
            }
        }
        .frame(width: 64, height: 64)
        .overlay(alignment: .bottomTrailing) {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                .offset(x: 4, y: 4)
        }
    }
}

// MARK: - 标题栏窗口移动手势

/// 标题栏区域叠加层：mouseDown 调 window.performDrag 移动窗口（macOS 窗口心智，零学习成本）
private struct NestTitleBarDragHandler: NSViewRepresentable {
    func makeNSView(context: Context) -> NestTitleBarDragView { NestTitleBarDragView() }
    func updateNSView(_ nsView: NestTitleBarDragView, context: Context) {}
}

private final class NestTitleBarDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        // 交给系统接管窗口移动（模态拖拽循环），无需依赖 isMovable
        window?.performDrag(with: event)
    }
}

// MARK: - 拖出基类（封装 mouseDown/mouseDragged/NSDraggingSource/URL 生命周期）

/// 封装暂存巢拖出的公共逻辑：阈值判定、组装 draggingItems、security-scoped URL 管理、
/// autoRemoveShelfItems 联动。子类只需提供 `resolveDragMembers()` 和 `previewImage`。
private class NestDragSourceView: NSView, NSDraggingSource {
    /// 拖拽预览图（整体拖出时为堆叠预览，单个拖出时为 nil 用条目图标）
    var previewImage: NSImage?

    private var mouseDownEvent: NSEvent?
    private let dragThreshold: CGFloat = 3.0
    private var draggedURLs: [URL] = []

    /// 子类提供：本次拖出包含的条目列表
    func resolveDragMembers() -> [ShelfItem] { [] }

    /// 子类可选覆盖：拖出成功后是否联动移除（默认跟随 autoRemoveShelfItems）
    func shouldAutoRemove(after operation: NSDragOperation) -> Bool {
        Defaults[.autoRemoveShelfItems] && !operation.isEmpty
    }

    // MARK: - 右键菜单兜底

    override func rightMouseDown(with event: NSEvent) {
        let members = resolveDragMembers()
        guard !members.isEmpty else {
            super.rightMouseDown(with: event)
            return
        }
        let menu = NSMenu()
        let moveAll = NSMenuItem(title: "全部移到文件夹…", action: #selector(moveAllAction(_:)), keyEquivalent: "")
        moveAll.target = self
        menu.addItem(moveAll)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func moveAllAction(_ sender: Any?) {
        let members = resolveDragMembers()
        guard !members.isEmpty else { return }
        Task { @MainActor in
            await NestDragExportService.moveAllToFolder(members: members)
        }
    }

    // MARK: - mouseDown / mouseDragged

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownEvent else {
            super.mouseDragged(with: event)
            return
        }
        let dragDistance = hypot(
            event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
            event.locationInWindow.y - mouseDownEvent.locationInWindow.y
        )
        if dragDistance > dragThreshold {
            self.mouseDownEvent = nil
            startDragSession(with: event)
        } else {
            super.mouseDragged(with: event)
        }
    }

    // MARK: - 组装 draggingItems

    private func startDragSession(with event: NSEvent) {
        let members = resolveDragMembers()
        var draggingItems: [NSDraggingItem] = []
        for member in members {
            guard let pasteboardItem = ShelfDragPayloadWriter.makePasteboardItem(
                for: member,
                securityScopedURLs: &draggedURLs
            ) else { continue }
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            let image = previewImage ?? member.icon
            draggingItem.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
            draggingItems.append(draggingItem)
        }
        guard !draggingItems.isEmpty else { return }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        if Defaults[.copyOnDrag] {
            return [.copy]
        }
        switch context {
        case .outsideApplication:
            return [.copy, .move]
        case .withinApplication:
            return [.copy, .move, .generic]
        @unknown default:
            return [.copy]
        }
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        ShelfSelectionModel.shared.beginDrag()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        ShelfSelectionModel.shared.endDrag()

        for url in draggedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        draggedURLs.removeAll()

        // 联动 autoRemoveShelfItems：移除本次拖出的成员（remove 会自动关闭空组面板）
        if shouldAutoRemove(after: operation) {
            ShelfStateViewModel.shared.remove(resolveDragMembers())
        }
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { false }
}

// MARK: - 整体拖出（标题栏抓手 + 网格空白区）

/// 整体拖出叠加层：拖动 → 发起包含组内全部 fileURL 的 drag session
private struct NestGroupDragHandler: NSViewRepresentable {
    let members: [ShelfItem]
    let previewImage: NSImage?

    func makeNSView(context: Context) -> NestGroupDragView {
        let view = NestGroupDragView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: NestGroupDragView, context: Context) {
        update(nsView)
    }

    private func update(_ view: NestGroupDragView) {
        view.members = members
        view.previewImage = previewImage
    }
}

private final class NestGroupDragView: NestDragSourceView {
    var members: [ShelfItem] = []
    override func resolveDragMembers() -> [ShelfItem] { members }
}

// MARK: - 单个条目拖出（cell 级）

/// 覆盖单个 cell：拖动该条目独立拖出（不触发整体拖出）
private struct NestCellDragHandler: NSViewRepresentable {
    let item: ShelfItem

    func makeNSView(context: Context) -> NestCellDragView {
        let view = NestCellDragView()
        view.item = item
        return view
    }

    func updateNSView(_ nsView: NestCellDragView, context: Context) {
        nsView.item = item
    }
}

private final class NestCellDragView: NestDragSourceView {
    var item: ShelfItem?
    override func resolveDragMembers() -> [ShelfItem] { item.map { [$0] } ?? [] }
    // 单个拖出不需要 willBegin 的 beginDrag（整体拖出才需要），但基类统一调用无副作用
}

// MARK: - 右键菜单「全部移到文件夹…」服务

/// NSOpenPanel 选目标文件夹，按 copyOnDrag 复制/移动全部文件（文件操作在后台线程执行）
enum NestDragExportService {
    @MainActor
    static func moveAllToFolder(members: [ShelfItem]) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = Defaults[.copyOnDrag] ? "复制到此" : "移动到此"
        guard panel.runModal() == .OK, let dest = panel.url else { return }

        let copy = Defaults[.copyOnDrag]
        // 主线程解析 URL（涉及 bookmark 解析，需主线程），后台线程执行文件操作
        let urls: [URL] = members.compactMap { ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: $0) }
        let memberIDs = members.map(\.id)

        let successCount = await Task.detached(priority: .userInitiated) {
            var count = 0
            for url in urls {
                let target = dest.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path) { continue } // 已存在跳过
                do {
                    if copy {
                        try FileManager.default.copyItem(at: url, to: target)
                    } else {
                        try FileManager.default.moveItem(at: url, to: target)
                    }
                    count += 1
                } catch {
                    NSLog("⚠️ 全部移到文件夹失败 \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return count
        }.value

        // 联动 autoRemoveShelfItems：成功后从文件架移除（remove 会自动关闭空组面板）
        if Defaults[.autoRemoveShelfItems] && successCount > 0 {
            let members = ShelfStateViewModel.shared.items.filter { memberIDs.contains($0.id) }
            if !members.isEmpty {
                ShelfStateViewModel.shared.remove(members)
            }
        }
    }
}
