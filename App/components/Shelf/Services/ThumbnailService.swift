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
    private var cacheKeys: Set<String> = []
    private var pendingRequests: [String: Task<NSImage?, Never>] = [:]
    private let thumbnailGenerator = QLThumbnailGenerator.shared

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
                let cost = Int(thumbnail.size.width * thumbnail.size.height) * 4
                cache.setObject(thumbnail, forKey: cacheKey as NSString, cost: cost)
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
    }
    
    func clearCache(for url: URL) {
        let prefix = url.path
        let toRemove = cacheKeys.filter { $0.hasPrefix(prefix) }
        for key in toRemove {
            cache.removeObject(forKey: key as NSString)
        }
        cacheKeys.subtract(toRemove)
    }
    
    // MARK: - Private Methods

    private func makeCacheKey(for url: URL, size: CGSize) -> String {
        let modificationDate: String
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let date = attrs[.modificationDate] as? Date {
            modificationDate = "\(date.timeIntervalSince1970)"
        } else {
            modificationDate = "unknown"
        }
        return "\(url.path)|\(size.width)x\(size.height)|\(modificationDate)"
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
