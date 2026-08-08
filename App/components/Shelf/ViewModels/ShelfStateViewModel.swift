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
        toRemove.forEach { $0.cleanupStoredData() }
        // deleteGroup 由 FloatingNestManager.deleteGroup 调用，面板已在那里关闭
    }

    /// 按组取条目（保持 Shelf 顺序）
    func items(inGroup groupID: UUID) -> [ShelfItem] {
        items.filter { $0.groupID == groupID }
    }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

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
        item.cleanupStoredData()
        let removedGroupID = item.groupID
        items.removeAll { $0.id == item.id }
        // 删除后若所属组已空，关闭对应桌面巢（避免残留"载入中"空巢）
        if let gid = removedGroupID, !items.contains(where: { $0.groupID == gid }) {
            expandedGroupIDs.remove(gid)
            Task { @MainActor in
                FloatingNestManager.shared.closePanel(for: gid)
            }
        }
    }

    func clearAll() {
        let removed = items
        items = []
        removed.forEach { $0.cleanupStoredData() }
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

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    /// 载入拖拽内容。
    /// - Parameter intoGroup: 拖入既有巢时传入该巢 groupID，本批条目继承之；
    ///   拖入空巢胚时由 manager 先创建新 groupID 再传入；nil = 刘海 Shelf 直接拖入（保留批量成组开关）。
    func load(_ providers: [NSItemProvider], intoGroup groupID: UUID? = nil) {
        guard !providers.isEmpty else { return }
        isLoading = true
        Task { [weak self] in
            var dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                guard !dropped.isEmpty else {
                    self?.isLoading = false
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
            }
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            var keep: [ShelfItem] = []
            for item in self.items {
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if await bookmark.validate() {
                        keep.append(item)
                    } else {
                        item.cleanupStoredData()
                    }
                default:
                    keep.append(item)
                }
            }
            await MainActor.run { self.items = keep }
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
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

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
