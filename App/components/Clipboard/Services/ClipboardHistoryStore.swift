//
//  ClipboardHistoryStore.swift
//  DropNest
//
//  Created on 2026-08-07.
//  In-memory history state + dedup + pruning + JSON/blob persistence.
//  Persistence pattern mirrors ShelfPersistenceService.
//

import AppKit
import Defaults
import Foundation

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    @Published private(set) var items: [ClipboardItem] = [] {
        didSet { NotchViewModel.clipboardRowCount = items.count }
    }
    /// Hash of the content currently on the system pasteboard, used to mark
    /// which history row is "the current clipboard" with a persistent checkmark.
    @Published private(set) var currentContentHash: String?

    private let directory: URL
    private let blobsDirectory: URL
    private let fileURL: URL

    private var saveTask: Task<Void, Never>?
    /// 定期清理过期条目。pruneExpired 仅在启动加载时调用一次，长期运行（不重启）
    /// 会导致过期条目一直占用内存与磁盘。每 10 分钟检查一次（retentionDays=0 时跳过）。
    private var pruneTimer: Timer?

    /// 标记历史是否已从磁盘加载完成。加载完成前 items 为空，
    /// 启动瞬间复制的新条目会在 finishInitialLoad 中与磁盘历史合并。
    private var didLoadFromDisk = false

    /// 串行化插入链：保证提交顺序 = 完成顺序。
    /// insert 是 @MainActor 方法，insertChain 在主线程读写无竞态；
    /// detached task 内 await prev?.value 在后台线程等待前一个完成，不阻塞主线程。
    /// 无此机制时，大图（TIFF→PNG ~500ms）先复制、文本（~5ms）后复制会导致文本先 finishInsert，
    /// 大图后 finishInsert 插到 index 0，历史顺序颠倒（违反"最新在上"语义）。
    private var insertChain: Task<Void, Never>?

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        if support == nil {
            print("⚠️ Clipboard history: Application Support unavailable, falling back to temporary directory")
        }
        directory = (support ?? fm.temporaryDirectory)
            .appendingPathComponent("DropNest", isDirectory: true)
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
        blobsDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        do {
            try fm.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ Clipboard history: failed to create blobs directory: \(error.localizedDescription)")
        }
        fileURL = directory.appendingPathComponent("items.json")

        // 历史 load + prune 移到后台线程，避免大 JSON 反序列化阻塞主线程启动。
        // load(from:) 是纯函数（只读 url + 内部新建 decoder），不捕获任何可变/非 Sendable 状态，
        // 可安全在 detached task 执行；解码完成后回主线程赋值 items 并裁剪。
        let url = fileURL
        Task.detached(priority: .utility) { [weak self] in
            let loaded = Self.load(from: url)
            await self?.finishInitialLoad(loaded)
        }

        // 定期清理过期条目（每 10 分钟）。retentionDays=0 时 pruneExpired 内部跳过。
        let timer = Timer(timeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneExpired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    /// 主线程收尾：合并磁盘历史与加载期间的新插入，再裁剪。
    private func finishInitialLoad(_ loaded: [ClipboardItem]) {
        guard !didLoadFromDisk else { return }
        didLoadFromDisk = true
        // 加载期间若有新条目（prepend 到 items），保留在前；历史 append 在后。
        items = items + loaded
        pruneExpired()
        prune()
        if !items.isEmpty { scheduleSave() } // persist any capacity-trimmed state
    }

    // MARK: - Insert / dedup

    /// 入口（@MainActor）：重活（TIFF→PNG、SHA256、blob 写盘）全部在后台线程完成，
    /// 主线程只承担去重判定与 items 数组变更。
    /// 通过 insertChain 串行化：新 task 等待前一个完成后再执行，保证 finishInsert
    /// 按提交顺序执行（而非完成顺序），避免快速连续复制时历史顺序颠倒。
    func insert(_ capture: CapturedContent) {
        NotchTabPreference.lastActivity = .copy
        let blobsDir = blobsDirectory
        let prev = insertChain
        insertChain = Task.detached(priority: .utility) { [weak self] in
            // 等待前一个 insert 完成，保证提交顺序 = 完成顺序。
            // await 在后台线程等待，不阻塞主线程。
            _ = await prev?.value
            // TIFF → PNG 转换（后台；截图类内容的最高开销环节）
            var imageData = capture.imageData
            if imageData == nil, let tiff = capture.tiffData,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                imageData = png
            }

            // SHA256 哈希（后台；大图可达 10MB）
            let hash = ClipboardItem.makeHash(
                text: capture.text,
                imageData: imageData,
                fileURLs: capture.fileURLs,
                linkURL: capture.linkURL
            )

            // blob 写盘（后台）。若主线程判重命中，这些文件会被立即删除。
            // RTF/HTML 大载荷落盘，避免 base64 内联 items.json 常驻内存（各可达 10MB）；
            // 小载荷（< 4KB）直接内联到 JSON，避免为微小格式化文本创建独立 blob 文件
            // （文件系统元数据开销 > 数据本身）。图片始终落盘（截图类体积大）。
            let blobInlineThreshold = 4 * 1024
            func writeBlob(_ data: Data?, ext: String) -> String? {
                guard let data else { return nil }
                let name = UUID().uuidString + ext
                do {
                    try data.write(to: blobsDir.appendingPathComponent(name), options: .atomic)
                    return name
                } catch {
                    print("❌ Clipboard history: failed to write \(ext) blob: \(error.localizedDescription)")
                    return nil
                }
            }
            /// 小载荷内联，大载荷落盘。返回 (blobName, inlineData)，二者互斥。
            func storePayload(_ data: Data?, ext: String) -> (blobName: String?, inline: Data?) {
                guard let data else { return (nil, nil) }
                if data.count < blobInlineThreshold { return (nil, data) }
                return (writeBlob(data, ext: ext), nil)
            }
            let imageBlobName = writeBlob(imageData, ext: ".png")
            let (rtfBlobName, rtfInline) = storePayload(capture.rtfData, ext: ".rtf")
            let (htmlBlobName, htmlInline) = storePayload(capture.htmlData, ext: ".html")

            let item = ClipboardItem(
                text: capture.text,
                rtfData: rtfInline,
                htmlData: htmlInline,
                imageBlobName: imageBlobName,
                rtfBlobName: rtfBlobName,
                htmlBlobName: htmlBlobName,
                fileURLs: capture.fileURLs,
                linkURL: capture.linkURL,
                sourceAppBundleID: capture.sourceAppBundleID,
                contentHash: hash
            )
            await self?.finishInsert(item)
        }
    }

    /// 主线程收尾：去重 / 插入 / 修剪 / 调度保存
    private func finishInsert(_ item: ClipboardItem) {
        let hash = item.contentHash

        // Dedup: identical content already recorded → bump to top.
        if let index = items.firstIndex(where: { $0.contentHash == hash }) {
            // 新写的 blob 无引用（复用既有条目的 blob），立即清理
            let existing = items[index]
            for name in [item.imageBlobName, item.rtfBlobName, item.htmlBlobName] {
                if let name, name != existing.imageBlobName, name != existing.rtfBlobName, name != existing.htmlBlobName {
                    try? FileManager.default.removeItem(at: blobsDirectory.appendingPathComponent(name))
                }
            }
            var bumped = items.remove(at: index)
            bumped.lastCopiedAt = Date()
            bumped.copyCount += 1
            items.insert(bumped, at: 0)
            currentContentHash = hash
            scheduleSave()
            return
        }

        items.insert(item, at: 0)
        currentContentHash = hash
        prune()
        scheduleSave()
    }

    // MARK: - Pruning

    /// Capacity pruning — pinned items never evicted.
    private func prune() {
        let maxItems = Defaults[.clipboardMaxItems]
        guard items.count > maxItems else { return }

        var kept: [ClipboardItem] = []
        var evicted: [ClipboardItem] = []
        var unpinnedCount = 0
        let budget = max(0, maxItems - items.filter(\.isPinned).count)

        for item in items {
            if item.isPinned {
                kept.append(item)
            } else if unpinnedCount < budget {
                unpinnedCount += 1
                kept.append(item)
            } else {
                evicted.append(item)
            }
        }
        items = kept
        evicted.forEach(removeBlob)
    }

    /// Retention pruning — 0 days means keep forever.
    private func pruneExpired() {
        let days = Defaults[.clipboardRetentionDays]
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-TimeInterval(days) * 86400)
        let expired = items.filter { !$0.isPinned && $0.lastCopiedAt < cutoff }
        guard !expired.isEmpty else { return }
        items.removeAll { !$0.isPinned && $0.lastCopiedAt < cutoff }
        expired.forEach(removeBlob)
        scheduleSave()
    }

    // MARK: - Item actions

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let willPin = !items[index].isPinned
        items[index].isPinned.toggle()
        if willPin {
            enforcePinnedCap()
        }
        scheduleSave()
    }

    /// 置顶数量上限——超出时自动取消最旧的置顶，防止 pinned 条目永不淘汰
    /// 导致内存/磁盘无界增长。只取消置顶标记，不删除条目本身。
    private func enforcePinnedCap() {
        let pinnedIndices = items.indices.filter { items[$0].isPinned }
        guard pinnedIndices.count > Self.maxPinnedItems else { return }
        // items 按时间倒序，最旧的置顶在末尾
        for idx in pinnedIndices.dropFirst(Self.maxPinnedItems) {
            items[idx].isPinned = false
        }
        print("📋 Clipboard history: pinned cap (\(Self.maxPinnedItems)) reached, oldest pin(s) released")
    }

    /// 置顶条目数上限
    private static let maxPinnedItems = 100

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        removeBlob(item)
        scheduleSave()
    }

    func clearAll() {
        // 标记不再接受磁盘加载：避免用户在启动加载完成前清空，
        // 随后 finishInitialLoad 又把磁盘历史 append 回来导致清空失效。
        didLoadFromDisk = true
        let removed = items
        items = []
        currentContentHash = nil
        removed.forEach(removeBlob)
        scheduleSave()
    }

    /// Writes every stored representation back to the general pasteboard so
    /// pasting behaves like the original copy, then tells the monitor to
    /// ignore this self-inflicted change.
    func copyBackToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if let fileURLs = item.fileURLs, !fileURLs.isEmpty {
            pb.writeObjects(fileURLs as [NSURL])
        }
        if let blobName = item.imageBlobName,
           let data = try? Data(contentsOf: blobsDirectory.appendingPathComponent(blobName)) {
            pb.setData(data, forType: .png)
        }
        if let link = item.linkURL {
            pb.setString(link.absoluteString, forType: NSPasteboard.PasteboardType("public.url"))
        }
        // RTF/HTML：新格式从 blob 读，旧格式用内联数据（向后兼容）
        if let rtf = loadBlobData(name: item.rtfBlobName) ?? item.rtfData { pb.setData(rtf, forType: .rtf) }
        if let html = loadBlobData(name: item.htmlBlobName) ?? item.htmlData { pb.setData(html, forType: .html) }
        if let text = item.text { pb.setString(text, forType: .string) }

        currentContentHash = item.contentHash
        ClipboardMonitor.shared.syncAfterSelfWrite()
    }

    func blobURL(for item: ClipboardItem) -> URL? {
        guard let name = item.imageBlobName else { return nil }
        let url = blobsDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func removeBlob(_ item: ClipboardItem) {
        for name in [item.imageBlobName, item.rtfBlobName, item.htmlBlobName] {
            guard let name else { continue }
            try? FileManager.default.removeItem(at: blobsDirectory.appendingPathComponent(name))
        }
    }

    /// 读取 blob 文件内容（RTF/HTML 回贴路径用）
    private func loadBlobData(name: String?) -> Data? {
        guard let name else { return nil }
        return try? Data(contentsOf: blobsDirectory.appendingPathComponent(name))
    }

    // MARK: - Persistence

    /// Debounced write — rapid copies coalesce into a single disk hit.
    /// encode + write 都在后台线程执行，主线程只捕获 items 快照。
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = items
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()
                // 每次保存用独立 encoder：后台线程不复用共享实例，规避并发风险
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try Task.checkCancellation()
                try data.write(to: url, options: .atomic)
            } catch is CancellationError {
                // 防抖合并：被更新的 save 取代，正常路径
            } catch {
                print("❌ Failed to save clipboard history: \(error.localizedDescription)")
            }
        }
    }

    /// 立即保存（应用退出等场景），跳过防抖延迟，阻塞当前线程写入
    func saveImmediately() {
        saveTask?.cancel()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ Failed to synchronously save clipboard history: \(error.localizedDescription)")
        }
    }

    /// 从磁盘加载历史（纯函数，可安全在后台线程执行）。
    /// 容错路径：单条损坏时逐条 salvage，避免整份历史因一条坏数据丢失。
    private nonisolated static func load(from url: URL) -> [ClipboardItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: url) else { return [] }

        if let decoded = try? decoder.decode([ClipboardItem].self, from: data) {
            return decoded
        }

        // Tolerant path: salvage valid entries one by one (Shelf-style).
        do {
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
            var valid: [ClipboardItem] = []
            var failed = 0
            for jsonItem in jsonArray {
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: jsonItem)
                    valid.append(try decoder.decode(ClipboardItem.self, from: itemData))
                } catch { failed += 1 }
            }
            if failed > 0 {
                print("📋 Clipboard history: loaded \(valid.count), discarded \(failed) corrupted")
            }
            return valid
        } catch {
            print("❌ Failed to parse clipboard history file: \(error.localizedDescription)")
            return []
        }
    }
}
