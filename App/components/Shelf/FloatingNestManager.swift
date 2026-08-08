//
//  FloatingNestManager.swift
//
//  悬浮暂存巢群管理器（v2.1 重写）：
//  - 多实例管理：panels: [UUID: FloatingNestPanel]（key = groupID）
//  - 空巢胚：拖拽期间保证存在一个浅色占位巢，被 drop 后孵化为正式巢
//  - 流转 API：showAll()/dockAll()/toggle(groupID:)/dock(groupID:)
//  - 位置记忆：正式巢位置按 groupID 存 Defaults 字典
//  与 AppDelegate 的刘海窗口体系完全隔离，不进 NotchSpaceManager。
//

import AppKit
import Defaults

@MainActor
final class FloatingNestManager {
    static let shared = FloatingNestManager()

    /// 正式巢面板（key = groupID）
    private var panels: [UUID: FloatingNestPanel] = [:]
    /// 当前空巢胚（同一时刻最多一个）
    private var ghostPanel: FloatingNestPanel?
    /// 空巢胚被 drop 时暂存的 providers，孵化后由 manager 调 load(intoGroup:)
    var pendingDropProviders: [NSItemProvider]?

    /// 落巢成功回调（参数为面板所在屏幕），由 AppDelegate 接线用于在刘海侧展示文件架
    var onDeposit: ((NSScreen) -> Void)?

    private init() {}

    /// 是否有可见的正式巢面板（供 ShelfView 的巢群按钮判断状态）
    var hasVisiblePanels: Bool { !panels.isEmpty }

    // MARK: - 启动接线

    /// 接线摇晃检测回调；启动时调用一次
    func start() {
        ShakeGestureDetector.shared.onShake = { [weak self] point in
            self?.summonGhost(at: point)
        }
    }

    // MARK: - 拖拽生命周期

    /// 拖拽开始（DragDetector.onContentDragStart）：已有巢进入可接收态；若开启自动显示且无空巢胚 → 在指针附近创建
    func handleDragStart(at point: CGPoint? = nil) {
        guard Defaults[.floatingNestEnabled], Defaults[.boringShelf] else { return }

        // 已有巢进入高亮态（通过 orderFront 重新激活）
        for panel in panels.values {
            panel.orderFrontRegardless()
        }

        // nestShowOnDragStart = true 时自动创建空巢胚
        guard Defaults[.nestShowOnDragStart] else { return }
        guard ghostPanel == nil else { return }
        let p = point ?? NSEvent.mouseLocation
        createGhost(at: p)
    }

    /// 拖拽结束（DragDetector.onContentDragEnd）：销毁未使用的空巢胚
    /// 注意：孵化是异步的（onHatch 通过 DispatchQueue.main.async 延迟执行），
    /// 若 drop 刚发生，hatchGhost 可能还未执行，此时 ghostPanel 仍非 nil 但即将孵化。
    /// 用延迟 + 二次检查避免误删正在孵化的空巢胚。
    func handleDragEnd() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }
            // 仅当 ghostPanel 仍存在（未被 hatchGhost 转移到 panels）时才销毁
            self.dismissGhostIfUnused()
        }
    }

    // MARK: - 空巢胚

    /// 摇晃召唤：在指针附近创建空巢胚（「仅摇晃召唤」模式下的手动入口）
    func summonGhost(at point: CGPoint) {
        guard Defaults[.floatingNestEnabled], Defaults[.boringShelf] else { return }
        // 若已有空巢胚则移动它，否则创建
        if let ghost = ghostPanel {
            ghost.show(at: point)
        } else {
            createGhost(at: point)
        }
    }

    private func createGhost(at point: CGPoint) {
        let ghost = FloatingNestPanel(groupID: UUID(), isGhost: true)
        ghost.onHatch = { [weak self] panel in
            self?.hatchGhost(panel)
        }
        ghostPanel = ghost
        ghost.show(at: point)
    }

    /// 空巢胚被 drop → 创建真实 groupID，孵化为正式巢，载入拖拽内容
    private func hatchGhost(_ panel: FloatingNestPanel) {
        let realGroupID = UUID()
        panel.hatch(to: realGroupID)
        panel.onDock = { [weak self] gid in
            self?.dock(groupID: gid)
        }
        panel.onDelete = { [weak self] gid in
            self?.deleteGroup(gid)
        }

        // 载入暂存的 providers 到新 groupID
        if let providers = pendingDropProviders {
            pendingDropProviders = nil
            // 载入完成后回调再调整窗口尺寸/判定回滚（替代硬编码 sleep 竞态）
            ShelfStateViewModel.shared.load(providers, intoGroup: realGroupID) { [weak self, weak panel] in
                guard let panel else { return }
                let members = ShelfStateViewModel.shared.items(inGroup: realGroupID)
                if members.isEmpty {
                    // load 失败/无有效内容 → 回滚：关闭空巢并清理位置记忆
                    panel.hide()
                    self?.panels.removeValue(forKey: realGroupID)
                    var positions = Defaults[.nestPositions]
                    positions.removeValue(forKey: realGroupID.uuidString)
                    Defaults[.nestPositions] = positions
                } else {
                    panel.adjustSize(for: members.count)
                }
            }
        }

        // 从 ghost 转为正式巢
        ghostPanel = nil
        panels[realGroupID] = panel

        // 通知刘海侧展示文件架
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main {
            onDeposit?(screen)
        }
    }

    /// 销毁未使用的空巢胚（拖拽结束/Esc/点击外部时）
    private func dismissGhostIfUnused() {
        guard let ghost = ghostPanel else { return }
        ghost.hide()
        ghostPanel = nil
    }

    // MARK: - 流转 API（刘海 ⇄ 桌面）

    /// 一键展开全部集合为桌面巢
    func showAll() {
        guard Defaults[.floatingNestEnabled], Defaults[.boringShelf] else { return }
        let tvm = ShelfStateViewModel.shared
        let groupIDs = Set(tvm.items.compactMap { $0.groupID })
        for gid in groupIDs where panels[gid] == nil {
            showPanel(for: gid, at: nil)
        }
    }

    /// 一键收起全部桌面巢（集合保留在刘海 Shelf）
    func dockAll() {
        let snapshot = panels
        panels.removeAll()
        for (gid, panel) in snapshot {
            savePosition(for: gid, panel: panel)
            panel.hide()
        }
    }

    /// 切换单个集合的桌面巢展开/收起状态
    func toggle(groupID: UUID) {
        if let panel = panels[groupID] {
            // 已展开 → 收起
            savePosition(for: groupID, panel: panel)
            panel.hide()
            panels.removeValue(forKey: groupID)
        } else {
            // 未展开 → 展开
            showPanel(for: groupID, at: nil)
        }
    }

    /// 巢的收起按钮调用（收进刘海，集合保留在 Shelf）
    func dock(groupID: UUID) {
        guard let panel = panels[groupID] else { return }
        savePosition(for: groupID, panel: panel)
        panel.hide()
        panels.removeValue(forKey: groupID)
    }

    /// 关闭指定 groupID 的桌面巢并清除位置记忆（用于解散集合/组内条目全部移除等场景）
    func closePanel(for groupID: UUID) {
        if let panel = panels[groupID] {
            panel.hide()
            panels.removeValue(forKey: groupID)
        }
        var positions = Defaults[.nestPositions]
        if positions.removeValue(forKey: groupID.uuidString) != nil {
            Defaults[.nestPositions] = positions
        }
    }

    /// 删除集合：移除组内全部条目并关闭对应桌面巢
    func deleteGroup(_ groupID: UUID) {
        if let panel = panels[groupID] {
            panel.hide()
            panels.removeValue(forKey: groupID)
        }
        // 数据清理（Defaults 写入 + items 移除触发 SwiftUI 重绘 + 临时文件删除）
        // 推迟到下一个 runloop，避免阻塞 panel 关闭的视觉渲染
        Task { @MainActor in
            var positions = Defaults[.nestPositions]
            positions.removeValue(forKey: groupID.uuidString)
            Defaults[.nestPositions] = positions
            ShelfStateViewModel.shared.deleteGroup(groupID)
        }
    }

    // MARK: - 位置记忆

    private func showPanel(for groupID: UUID, at point: CGPoint?) {
        let members = ShelfStateViewModel.shared.items(inGroup: groupID)
        let panel = FloatingNestPanel(groupID: groupID, isGhost: false)
        panel.onDock = { [weak self] gid in
            self?.dock(groupID: gid)
        }
        panel.onDelete = { [weak self] gid in
            self?.deleteGroup(gid)
        }

        // 设置窗口尺寸
        let size = NestGridLayout.size(for: members.count)
        panel.setContentSize(size)
        panel.invalidateShadow()

        // 还原记忆位置，否则默认指针附近；两条路径都走入场动画
        if let saved = loadPosition(for: groupID) {
            panel.setFrameOrigin(saved)
            panel.showAtCurrentFrame()
        } else {
            let p = point ?? NSEvent.mouseLocation
            panel.show(at: p)
        }

        panels[groupID] = panel
    }

    private func savePosition(for groupID: UUID, panel: FloatingNestPanel) {
        let origin = panel.frame.origin
        let encoded = "\(origin.x),\(origin.y)"
        var positions = Defaults[.nestPositions]
        positions[groupID.uuidString] = encoded
        Defaults[.nestPositions] = positions
    }

    private func loadPosition(for groupID: UUID) -> NSPoint? {
        guard let encoded = Defaults[.nestPositions][groupID.uuidString] else { return nil }
        let parts = encoded.split(separator: ",")
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        return NSPoint(x: x, y: y)
    }

    // MARK: - 清理

    /// 应用退出时清理全部巢窗
    func cleanup() {
        for panel in panels.values { panel.hide() }
        panels.removeAll()
        dismissGhostIfUnused()
    }

    /// 兼容旧 API：隐藏全部（applicationWillTerminate 等场景调用）
    func hide() {
        dockAll()
        dismissGhostIfUnused()
    }

    /// 兼容旧 API：落巢转发
    func notifyDeposit(on screen: NSScreen) {
        onDeposit?(screen)
    }
}
