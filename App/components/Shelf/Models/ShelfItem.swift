//
//  ShelfItem.swift
//  DropNest
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Foundation

enum ShelfItemKind: Codable, Equatable, Hashable, Sendable {
    case file(bookmark: Data)
    case text(string: String)
    case link(url: URL)

    enum CodingKeys: String, CodingKey { case type, value }

    enum KindTag: String, Codable { case file, text, link }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindTag.self, forKey: .type)
        switch type {
        case .file:
            let data = try container.decode(Data.self, forKey: .value)
            self = .file(bookmark: data)
        case .text:
            self = .text(string: try container.decode(String.self, forKey: .value))
        case .link:
            self = .link(url: try container.decode(URL.self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .file(let bookmark):
            try container.encode(KindTag.file, forKey: .type)
            try container.encode(bookmark, forKey: .value)
        case .text(let string):
            try container.encode(KindTag.text, forKey: .type)
            try container.encode(string, forKey: .value)
        case .link(let url):
            try container.encode(KindTag.link, forKey: .type)
            try container.encode(url, forKey: .value)
        }
    }

}

// MARK: - 解析结果缓存
/// 缓存书签解析 / 展示名 / 图标的计算结果，避免 displayName、icon、identityKey
/// 这些计算属性在主线程反复做书签解析与磁盘 I/O（尤其 add() 去重时对全部
/// 已存条目 map 一遍 identityKey）。
///
/// key 用书签数据本身：书签刷新（stale refresh 写回新 bookmark）后 key 变化，
/// 自动失效重新解析。只缓存成功案例，失败路径每次重试。
///
/// TTL 机制：每条缓存项 30 秒后自动失效。书签虽能跟踪文件移动/改名，但缓存了
/// 解析结果后不再重新 resolve，会导致文件改名后展示名/URL 仍指向旧路径（P0 回归）。
/// 30s TTL 兼顾性能（滚动爆发期命中率高）与时效（改名后最多 30s 自动修正）。
///
/// 非 @MainActor：用 NSLock 保护内部字典，可在任意线程安全访问。
/// 解耦自 ViewModel 单例，使 ShelfItem 的 fileURL/cleanupStoredData 不再依赖 MainActor。
final class ShelfItemResolutionCache {
    static let shared = ShelfItemResolutionCache()

    /// 带 TTL 的时间戳包装
    private struct Timed<Value> {
        let value: Value
        let storedAt: Date
    }

    /// 缓存 TTL：30 秒后自动失效，重新解析书签
    private let ttl: TimeInterval = 30

    /// bookmark data → (url, refreshedBookmark)
    private var contexts: [Data: Timed<(url: URL, bookmark: Data)>] = [:]
    /// bookmark data → 展示名
    private var displayNames: [Data: Timed<String>] = [:]
    /// 文件路径 → 图标
    private var icons: [String: Timed<NSImage>] = [:]

    /// 简单容量保护：超限时整体清空（代价仅是重新解析一轮）
    private let maxEntries = 1000

    private let lock = NSLock()

    func cachedContext(for bookmarkData: Data) -> (url: URL, bookmark: Data)? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = contexts[bookmarkData], !isExpired(entry) else {
            // 过期项惰性清除
            contexts.removeValue(forKey: bookmarkData)
            return nil
        }
        return entry.value
    }

    func storeContext(_ context: (url: URL, bookmark: Data), for bookmarkData: Data) {
        lock.lock(); defer { lock.unlock() }
        if contexts.count > maxEntries { contexts.removeAll(keepingCapacity: true) }
        contexts[bookmarkData] = Timed(value: context, storedAt: Date())
    }

    func cachedDisplayName(for bookmarkData: Data) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = displayNames[bookmarkData], !isExpired(entry) else {
            displayNames.removeValue(forKey: bookmarkData)
            return nil
        }
        return entry.value
    }

    func storeDisplayName(_ name: String, for bookmarkData: Data) {
        lock.lock(); defer { lock.unlock() }
        if displayNames.count > maxEntries { displayNames.removeAll(keepingCapacity: true) }
        displayNames[bookmarkData] = Timed(value: name, storedAt: Date())
    }

    func cachedIcon(forPath path: String) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = icons[path], !isExpired(entry) else {
            icons.removeValue(forKey: path)
            return nil
        }
        return entry.value
    }

    func storeIcon(_ icon: NSImage, forPath path: String) {
        lock.lock(); defer { lock.unlock() }
        if icons.count > maxEntries { icons.removeAll(keepingCapacity: true) }
        icons[path] = Timed(value: icon, storedAt: Date())
    }

    private func isExpired<V>(_ entry: Timed<V>) -> Bool {
        return Date().timeIntervalSince(entry.storedAt) > ttl
    }
}

/// 值类型本体非隔离（Codable/Equatable 可在后台线程使用，如批量 JSON 编码）。
/// fileURL/cleanupStoredData 已解耦 ViewModel 单例，可跨 actor 调用。
/// icon 仍标 @MainActor（NSWorkspace.shared.icon + NSImage 绘制属 AppKit 主线程惯例）。
struct ShelfItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var kind: ShelfItemKind
    var isTemporary: Bool
    /// 所属集合；nil = 独立条目。可选字段，旧 items.json 无需迁移
    var groupID: UUID?
    init(id: UUID = UUID(), kind: ShelfItemKind, isTemporary: Bool = false, groupID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.isTemporary = isTemporary
        self.groupID = groupID
    }

    var displayName: String {
        switch kind {
        case .file(let bookmarkData):
            if let cached = ShelfItemResolutionCache.shared.cachedDisplayName(for: bookmarkData) {
                return cached
            }
            let name = computeDisplayName(bookmarkData: bookmarkData)
            if !name.isEmpty {
                ShelfItemResolutionCache.shared.storeDisplayName(name, for: bookmarkData)
            }
            return name
        case .text(let string):
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case .link(let url):
            let s = url.absoluteString
            if s.hasPrefix("https://") {
                return String(s.dropFirst("https://".count))
            } else if s.hasPrefix("http://") {
                return String(s.dropFirst("http://".count))
            } else {
                return s
            }
        }
    }

    private func computeDisplayName(bookmarkData: Data) -> String {
        guard let resolvedURL = resolvedContext(for: bookmarkData)?.url else { return "" }

        // Check for stored data files (text blocks, weblocs, etc.) to provide friendly names
        if resolvedURL.pathExtension.lowercased() == "json" && resolvedURL.path.contains("TextBlocks") {
            do {
                let data = try Data(contentsOf: resolvedURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                struct TextBlockData: Codable {
                    let content: String
                    let title: String?
                    var displayTitle: String {
                        if let title = title, !title.isEmpty {
                            return title
                        }
                        let firstLine = content.components(separatedBy: .newlines).first ?? content
                        if firstLine.count > 50 {
                            return String(firstLine.prefix(47)) + "..."
                        }
                        return firstLine
                    }
                }
                if let textData = try? decoder.decode(TextBlockData.self, from: data) {
                    return textData.displayTitle
                }
            } catch {
                // Fall through to default naming
            }
        } else if resolvedURL.pathExtension.lowercased() == "webloc" && resolvedURL.path.contains("WebLocs") {
            do {
                let data = try Data(contentsOf: resolvedURL)
                if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let urlString = plist["URL"] as? String {
                    let title = plist["Title"] as? String
                    return title ?? urlString
                }
            } catch {
                // Fall through to default naming
            }
        }
        return (try? resolvedURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? resolvedURL.lastPathComponent
    }

    /// 文件 URL（解析 bookmark，不依赖 ViewModel 单例）。
    /// stale refresh 写回逻辑在 ShelfStateViewModel.resolveAndUpdateBookmark，
    /// 供需要更新 items 数组的场景调用；本属性只读 URL。
    var fileURL: URL? {
        guard case let .file(bookmarkData) = kind else { return nil }
        return resolvedContext(for: bookmarkData)?.url
    }

    @MainActor
    var icon: NSImage {
        guard case .file = kind else {
            return Self.thumbnailSymbolImage(systemName: kind.iconSymbolName) ?? NSImage()
        }
        // 用 resolvedContext 解析 URL，不依赖 ViewModel 单例
        if let resolvedURL = fileURL {
            let path = resolvedURL.path
            if let cached = ShelfItemResolutionCache.shared.cachedIcon(forPath: path) {
                return cached
            }
            let icon = NSWorkspace.shared.icon(forFile: path)
            ShelfItemResolutionCache.shared.storeIcon(icon, forPath: path)
            return icon
        }
        return NSImage()
    }


    /// 清理临时文件（非 @MainActor，可从后台线程调用）。
    func cleanupStoredData() {
        guard case let .file(bookmark) = kind,
              let context = resolvedContext(for: bookmark) else { return }

        let url = context.url

        // Handle temporary files
        if isTemporary {
            TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
            return
        }
    }
}

private extension ShelfItem {
   @MainActor
   static func thumbnailSymbolImage(
        systemName: String,
    size: CGSize = CGSize(width: 64, height: 80), 
    symbolPointSize: CGFloat = 38,
    backgroundColor: NSColor = NSColor.white,
    symbolColor: NSColor = NSColor.labelColor
    ) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = CGRect(origin: .zero, size: size)
        let cornerRadius = min(size.width, size.height) * 0.06
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: cornerRadius, yRadius: cornerRadius)
        backgroundColor.setFill()
        path.fill()

        if let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) {
            let symbolSize = CGSize(width: symbolPointSize, height: symbolPointSize)
            let symbolOrigin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )
            let symbolRect = CGRect(origin: symbolOrigin, size: symbolSize)
            symbol.draw(in: symbolRect)
        }

        return image
    }
}

// MARK: - Identity key for deduplication
extension ShelfItem {
    var identityKey: String {
        switch kind {
        case .file(let bookmark):
            if let url = resolvedContext(for: bookmark)?.url {
                return "file://" + url.standardizedFileURL.path
            }
            return "file://missing/" + bookmark.base64EncodedString()
        case .link(let u):
            return "link://" + u.absoluteString
        case .text(let s):
            return "text://" + s
        }
    }
}

// MARK: - Private helpers
private extension ShelfItemKind {
    var iconSymbolName: String {
        switch self {
        case .file:
            return "questionmark.circle"
        case .text:
            return "text.justifyleft"
        case .link:
            return "link"
        }
    }
}

extension ShelfItem {
    /// 解析 bookmark 为 (url, bookmark) 上下文，复用 ShelfItemResolutionCache（30s TTL）。
    /// 命中缓存时为纯内存操作；未命中时才执行 bookmark.resolveURL() 磁盘 IO。
    func resolvedContext(for bookmarkData: Data) -> (url: URL, bookmark: Data)? {
        let cache = ShelfItemResolutionCache.shared
        if let cached = cache.cachedContext(for: bookmarkData) {
            return cached
        }
        let bookmark = Bookmark(data: bookmarkData)
        guard let url = bookmark.resolveURL() else { return nil }
        let refreshedData = bookmark.refreshedData ?? bookmarkData
        let context = (url, refreshedData)
        cache.storeContext(context, for: bookmarkData)
        // 检测到 stale bookmark 时异步回写刷新数据到 items，
        // 避免 bookmark 跟踪链逐渐老化导致条目最终被 cleanupInvalidItems 误删。
        // ShelfItemResolutionCache 30s TTL 保证回写频率可控（同一 bookmark 30s 内最多一次）。
        if bookmark.refreshedData != nil && refreshedData != bookmarkData {
            let itemSnapshot = self
            Task { @MainActor in
                ShelfStateViewModel.shared.updateBookmark(for: itemSnapshot, bookmark: refreshedData)
            }
        }
        return context
    }
}
