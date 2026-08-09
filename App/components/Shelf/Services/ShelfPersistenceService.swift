//
//  ShelfPersistenceService.swift
//  DropNest
//
//  Created by Alexander on 2025-09-24.
//

import Foundation

// Access model types
@_exported import struct Foundation.URL


final class ShelfPersistenceService {
    static let shared = ShelfPersistenceService()

    let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var saveTask: Task<Void, Never>?

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        if support == nil {
            print("⚠️ Shelf persistence: Application Support unavailable, falling back to temporary directory")
        }
        let dir = (support ?? fm.temporaryDirectory).appendingPathComponent("DropNest", isDirectory: true).appendingPathComponent("Shelf", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("❌ Shelf persistence: failed to create directory \(dir.path): \(error.localizedDescription)")
        }
        fileURL = dir.appendingPathComponent("items.json")
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func load() -> [ShelfItem] {
        Self.load(from: fileURL)
    }

    /// 纯函数加载：只读 url + 内部新建 decoder，不捕获任何可变/非 Sendable 状态，
    /// 可安全在 detached task 执行，避免大 JSON 反序列化阻塞主线程启动。
    /// 与 ClipboardHistoryStore.load(from:) 保持同一范式。
    nonisolated static func load(from url: URL) -> [ShelfItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: url) else { return [] }

        // Try to decode as array first (normal case)
        if let items = try? decoder.decode([ShelfItem].self, from: data) {
            return items
        }

        // If array decoding fails, try to decode individual items (salvage path)
        do {
            // Parse as JSON array to get individual item data
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                print("⚠️ Shelf persistence file is not a valid JSON array")
                return []
            }

            var validItems: [ShelfItem] = []
            var failedCount = 0

            for (index, jsonItem) in jsonArray.enumerated() {
                do {
                    let itemData = try JSONSerialization.data(withJSONObject: jsonItem)
                    let item = try decoder.decode(ShelfItem.self, from: itemData)
                    validItems.append(item)
                } catch {
                    failedCount += 1
                    print("⚠️ Failed to decode shelf item at index \(index): \(error.localizedDescription)")
                }
            }

            if failedCount > 0 {
                print("📦 Successfully loaded \(validItems.count) shelf items, discarded \(failedCount) corrupted items")
            }

            return validItems
        } catch {
            print("❌ Failed to parse shelf persistence file: \(error.localizedDescription)")
            return []
        }
    }

    /// 防抖保存：800ms 内多次调用合并为一次；encode 和 write 都在后台线程执行，
    /// 避免拖拽批量导入时主线程被全量 JSON 编码阻塞。
    func save(_ items: [ShelfItem]) {
        saveTask?.cancel()
        let url = fileURL
        saveTask = Task.detached(priority: .utility) {
            do {
                try await Task.sleep(for: .milliseconds(800))
                try Task.checkCancellation()
                // 每次保存用独立 encoder：后台线程不复用共享实例，规避并发风险
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(items)
                try Task.checkCancellation()
                try data.write(to: url, options: .atomic)
            } catch is CancellationError {
                // 防抖合并：被更新的 save 取代，正常路径
            } catch {
                print("❌ Failed to save shelf items: \(error.localizedDescription)")
            }
        }
    }

    /// 立即保存（应用退出等场景）
    func saveImmediately(_ items: [ShelfItem]) {
        saveTask?.cancel()
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save shelf items: \(error.localizedDescription)")
        }
    }
}
