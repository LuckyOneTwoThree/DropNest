//
//  ThumbnailService.swift
//  DropNest
//
//  Created by Alexander on 2025-10-07.
//

import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 256 * 1024 * 1024 // 256MB
        return cache
    }()
    /// NSCache 不支持按前缀枚举键，故并行维护一份键集合以实现 clearCache(for:)。
    /// 上限保护：文件每次修改产生新 key，长期运行会只增不减——超限时整体重建。
    private var cacheKeys: Set<String> = []
    private let maxCacheKeys = 300
    private var pendingRequests: [String: Task<NSImage?, Never>] = [:]
    private let thumbnailGenerator = QLThumbnailGenerator.shared

    /// mtime 查询短时记忆（1s TTL）：滚动爆发期避免每次缓存查询都 stat 一次磁盘
    private var mtimeMemo: [String: (date: Date?, fetchedAt: Date)] = [:]

    private init() {}
    
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let cacheKey = makeCacheKey(for: url, size: size)
        
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }
        
        if let pending = pendingRequests[cacheKey] {
            return await pending.value
        }
        
        let task = Task<NSImage?, Never> {
            let thumbnail = await generateQuickLookThumbnail(for: url, size: size)
            if let thumbnail = thumbnail {
                // cost 按位图像素（width*height*4 字节）计，而非 NSImage.size（点），
                // 避免 Retina 下 256MB 上限被低估 2-4 倍
                let pixelCost: Int
                if let cg = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    pixelCost = cg.width * cg.height * 4
                } else {
                    pixelCost = Int(thumbnail.size.width * thumbnail.size.height) * 4
                }
                cache.setObject(thumbnail, forKey: cacheKey as NSString, cost: pixelCost)
                if cacheKeys.count > maxCacheKeys {
                    // key 集合只增不减的兜底：整体重建（NSCache 本身有淘汰，代价可接受）
                    cache.removeAllObjects()
                    cacheKeys.removeAll(keepingCapacity: true)
                }
                cacheKeys.insert(cacheKey)
            }
            pendingRequests[cacheKey] = nil
            return thumbnail
        }
        
        pendingRequests[cacheKey] = task
        return await task.value
    }
    
    func clearCache() {
        cache.removeAllObjects()
        cacheKeys.removeAll()
        mtimeMemo.removeAll()
    }

    func clearCache(for url: URL) {
        let prefix = url.path
        let toRemove = cacheKeys.filter { $0.hasPrefix(prefix) }
        for key in toRemove {
            cache.removeObject(forKey: key as NSString)
        }
        cacheKeys.subtract(toRemove)
        mtimeMemo.removeValue(forKey: prefix)
    }

    // MARK: - Private Methods

    private func makeCacheKey(for url: URL, size: CGSize) -> String {
        let stamp: String
        if let date = modificationDate(for: url.path) {
            stamp = "\(date.timeIntervalSince1970)"
        } else {
            stamp = "unknown"
        }
        return "\(url.path)|\(size.width)x\(size.height)|\(stamp)"
    }

    /// 带 1 秒 TTL 的 mtime 查询：同一文件 1 秒内只 stat 一次磁盘。
    /// 过期后重新 stat，文件被修改最多 1 秒后反映到新缓存键。
    private func modificationDate(for path: String) -> Date? {
        if let memo = mtimeMemo[path],
           Date().timeIntervalSince(memo.fetchedAt) < 1.0 {
            return memo.date
        }
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        if mtimeMemo.count > 500 { mtimeMemo.removeAll(keepingCapacity: true) }
        mtimeMemo[path] = (date, Date())
        return date
    }
    
    private func generateQuickLookThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        
        return await url.accessSecurityScopedResource { scopedURL in
            let request = QLThumbnailGenerator.Request(
                fileAt: scopedURL,
                size: size,
                scale: scale,
                representationTypes: .all
            )
            request.iconMode = true

            return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                thumbnailGenerator.generateBestRepresentation(for: request) { representation, _ in
                    if let rep = representation {
                        continuation.resume(returning: rep.nsImage)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension QLThumbnailRepresentation {
    var nsImage: NSImage {
        return NSImage(cgImage: self.cgImage, size: self.cgImage.size)
    }
}

extension CGImage {
    var size: NSSize {
        return NSSize(width: self.width, height: self.height)
    }
}
