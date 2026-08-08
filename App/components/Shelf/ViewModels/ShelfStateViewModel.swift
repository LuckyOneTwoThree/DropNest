//
//  ShelfStateViewModel.swift
//  DropNest
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit
import Defaults

/// 渲染单元：扁平 items 折叠为 单条目/集合 序列（保序：组内首条目位置即集合位置）
enum ShelfEntry: Identifiable, Equatable {
    case single(ShelfItem)
    case group(UUID, [ShelfItem])

    var id: UUID {
        switch self {
        case .single(let item): return item.id
        case .group(let groupID, _): return groupID
        }
    }
}

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }

    @Published var isLoading: Bool = false

    /// 就地展开查看的集合（会话内状态，不持久化）
    @Published private(set) var expandedGroupIDs: Set<UUID> = []

    func toggleGroupExpanded(_ groupID: UUID) {
        if expandedGroupIDs.contains(groupID) {
            expandedGroupIDs.remove(groupID)
        } else {
            expandedGroupIDs.insert(groupID)
        }
    }

    var isEmpty: Bool { items.isEmpty }

    /// 将扁平 items 折叠为渲染单元序列，组内首条目位置即集合位置
    var entries: [ShelfEntry] {
        var groupIndex: [UUID: Int] = [:]
        var result: [ShelfEntry] = []
        result.reserveCapacity(items.count)
        for item in items {
            guard let groupID = item.groupID else {
                result.append(.single(item))
                continue
            }
            if let idx = groupIndex[groupID], case .group(let id, var members) = result[idx] {
                members.append(item)
                result[idx] = .group(id, members)
            } else {
                groupIndex[groupID] = result.count
                result.append(.group(groupID, [item]))
            }
        }
        return result
    }

    // MARK: - 集合操作

    /// 给指定条目赋同一新 groupID，返回集合 ID
    @discardableResult
    func createGroup(from ids: Set<UUID>) -> UUID {
        let groupID = UUID()
        items = items.map { item in
            guard ids.contains(item.id) else { return item }
            var copy = item
            copy.groupID = groupID
            return copy
        }
        return groupID
    }

    /// 解散集合：组内条目 groupID 置 nil
    func dissolveGroup(_ groupID: UUID) {
        expandedGroupIDs.remove(groupID)
        items = items.map { item in
            guard item.groupID == groupID else { return item }
            var copy = item
            copy.groupID = nil
            return copy
        }
        // 解散后组不复存在，关闭对应桌面巢
        Task { @MainActor in
            FloatingNestManager.shared.closePanel(for: groupID)
        }
    }

    /// 删除集合：移除组内所有条目（区别于解散）
    func deleteGroup(_ groupID: UUID) {
        expandedGroupIDs.remove(groupID)
        let toRemove = items.filter { $0.groupID == groupID }
        items.removeAll { $0.groupID == groupID }
        // 临时文件清理在后台线程执行（cleanupStoredData 已解耦 @MainActor），
        // 避免批量删除时主线程被 FileManager IO 阻塞
        Task.detached(priority: .utility) {
            for item in toRemove {
                item.cleanupStoredData()
            }
        }
        // deleteGroup 由 FloatingNestManager.deleteGroup 调用，面板已在那里关闭
    }

    /// 按组取条目（保持 Shelf 顺序）
    func items(inGroup groupID: UUID) -> [ShelfItem] {
        items.filter { $0.groupID == groupID }
    }

    private init() {
        items = ShelfPersistenceService.shared.load()
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        items = merged
    }

    func remove(_ item: ShelfItem) {
        remove([item])
    }

    /// 批量移除条目：单次 items 变更（仅触发一次 @Published didSet 持久化）、
    /// 单个后台清理 task、统一空组检查。避免循环 remove(item) 导致 N 次持久化与 N 个 detached task。
    func remove(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        let idsToRemove = Set(items.map { $0.id })
        let affectedGroupIDs = Set(items.compactMap { $0.groupID })
        self.items.removeAll { idsToRemove.contains($0.id) }
        // 临时文件清理在后台线程执行（cleanupStoredData 已解耦 @MainActor）
        Task.detached(priority: .utility) {
            for item in items {
                item.cleanupStoredData()
            }
        }
        // 统一检查受影响组是否已空，关闭对应桌面巢（避免残留"载入中"空巢）
        for gid in affectedGroupIDs where !self.items.contains(where: { $0.groupID == gid }) {
            expandedGroupIDs.remove(gid)
            Task { @MainActor in
                FloatingNestManager.shared.closePanel(for: gid)
            }
        }
    }

    func clearAll() {
        let removed = items
        items = []
        // 临时文件清理在后台线程执行（cleanupStoredData 已解耦 @MainActor）
        Task.detached(priority: .utility) {
            for item in removed {
                item.cleanupStoredData()
            }
        }
        // 清空文件架时同步关闭所有桌面悬浮巢（否则巢会一直显示"载入中"）
        Task { @MainActor in
            FloatingNestManager.shared.dockAll()
        }
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }


    /// 载入拖拽内容。
    /// - Parameters:
    ///   - intoGroup: 拖入既有巢时传入该巢 groupID，本批条目继承之；
    ///     拖入空巢胚时由 manager 先创建新 groupID 再传入；nil = 刘海 Shelf 直接拖入（保留批量成组开关）。
    ///   - completion: 载入真正完成（或失败为空）后的回调，替代硬编码 sleep 等待
    func load(_ providers: [NSItemProvider], intoGroup groupID: UUID? = nil, completion: (() -> Void)? = nil) {
        guard !providers.isEmpty else {
            completion?()
            return
        }
        isLoading = true
        Task { [weak self] in
            var dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                guard !dropped.isEmpty else {
                    self?.isLoading = false
                    completion?()
                    return
                }
                if let groupID {
                    // v2：拖入既有巢 → 本批条目继承该巢 groupID（成组为默认语义）
                    for i in dropped.indices { dropped[i].groupID = groupID }
                } else if dropped.count > 1 && Defaults[.nestAutoGroupOnBatchDrop] {
                    // 刘海 Shelf 批量拖入仍可走独立开关
                    let gid = UUID()
                    for i in dropped.indices { dropped[i].groupID = gid }
                }
                // A successful shelf deposit marks the most recent activity.
                NotchTabPreference.lastActivity = .shelfDeposit
                self?.add(dropped)
                self?.isLoading = false
                completion?()
            }
        }
    }

    /// 清理失效书签条目。书签解析与 fileExists 是磁盘 I/O，必须离开主线程。
    /// 变化判断：仅当确实存在失效条目时才回写 items，避免无谓的 @Published didSet
    /// 触发持久化与全量重绘。
    func cleanupInvalidItems() {
        let snapshot = items  // MainActor 上快照（Sendable 值类型）
        Task.detached(priority: .utility) { [weak self] in
            var invalidIDs: Set<UUID> = []
            var invalid: [ShelfItem] = []
            for item in snapshot {
                guard case .file(let data) = item.kind else { continue }
                let bookmark = Bookmark(data: data)
                // validate() 标记 async 但内部为同步磁盘 I/O，后台执行不阻塞主线程
                if await bookmark.validate() { continue }
                invalidIDs.insert(item.id)
                invalid.append(item)
            }
            // 无失效条目则不触碰 items，避免无谓持久化与重绘
            guard !invalidIDs.isEmpty else { return }
            // cleanupStoredData 已解耦 @MainActor，可在后台调用
            for item in invalid {
                item.cleanupStoredData()
            }
            // 用失效 id 集合过滤当前 items（而非快照），保留并发增删期间的新增项
            await MainActor.run {
                self?.items.removeAll { invalidIDs.contains($0.id) }
                // 关闭因清理而变空的桌面巢
                let affectedGroupIDs = Set(invalid.compactMap { $0.groupID })
                for gid in affectedGroupIDs where !(self?.items.contains(where: { $0.groupID == gid }) ?? false) {
                    self?.expandedGroupIDs.remove(gid)
                    Task { @MainActor in
                        FloatingNestManager.shared.closePanel(for: gid)
                    }
                }
            }
        }
    }


    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }
}
