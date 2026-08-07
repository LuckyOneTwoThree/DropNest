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
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var saveTask: Task<Void, Never>?

    private init() {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = (support ?? fm.temporaryDirectory)
            .appendingPathComponent("boringNotch", isDirectory: true)
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
        blobsDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        try? fm.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("items.json")
        encoder.outputFormatting = [.prettyPrinted]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        items = load()
        pruneExpired()
        prune()
        if !items.isEmpty { save() } // persist any capacity-trimmed state
    }

    // MARK: - Insert / dedup

    func insert(_ capture: CapturedContent) {
        NotchTabPreference.lastActivity = .copy

        let hash = ClipboardItem.makeHash(
            text: capture.text,
            imageData: capture.imageData,
            fileURLs: capture.fileURLs,
            linkURL: capture.linkURL
        )

        // Dedup: identical content already recorded → bump to top.
        if let index = items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = items.remove(at: index)
            existing.lastCopiedAt = Date()
            existing.copyCount += 1
            items.insert(existing, at: 0)
            currentContentHash = hash
            scheduleSave()
            return
        }

        var imageBlobName: String?
        if let imageData = capture.imageData {
            let name = UUID().uuidString + ".png"
            let blobURL = blobsDirectory.appendingPathComponent(name)
            if (try? imageData.write(to: blobURL, options: .atomic)) != nil {
                imageBlobName = name
            }
        }

        let item = ClipboardItem(
            text: capture.text,
            rtfData: capture.rtfData,
            htmlData: capture.htmlData,
            imageBlobName: imageBlobName,
            fileURLs: capture.fileURLs,
            linkURL: capture.linkURL,
            sourceAppBundleID: capture.sourceAppBundleID,
            contentHash: hash
        )
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
        items[index].isPinned.toggle()
        scheduleSave()
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        removeBlob(item)
        scheduleSave()
    }

    func clearAll() {
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
        if let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
        if let html = item.htmlData { pb.setData(html, forType: .html) }
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
        guard let name = item.imageBlobName else { return }
        try? FileManager.default.removeItem(at: blobsDirectory.appendingPathComponent(name))
    }

    // MARK: - Persistence

    /// Debounced write — rapid copies coalesce into a single disk hit.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    private func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

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
