//
//  ClipboardHistoryViewModel.swift
//  DropNest
//
//  Created on 2026-08-07.
//

import AppKit
import Foundation

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    static let shared = ClipboardHistoryViewModel()

    @Published var searchText: String = "" {
        didSet { refreshDisplayedItems(from: ClipboardHistoryStore.shared.items) }
    }
    /// Brief "已复制" visual feedback target after tapping an item.
    @Published var lastCopiedID: UUID?

    /// Cached sort + filter result. The history list reads this instead of
    /// recomputing `displayedItems` on every keystroke / body evaluation.
    @Published private(set) var cachedDisplayedItems: [ClipboardItem] = []

    private var feedbackTask: Task<Void, Never>?

    /// Cache invalidation tokens — the displayed list is recomputed only when
    /// the store contents or the active query actually change.
    private var lastStoreCount: Int = -1
    private var lastQuery: String = ""
    private var lastItems: [ClipboardItem] = []

    private init() {
        // Pre-populate the cache so the first render shows items immediately.
        refreshDisplayedItems(from: ClipboardHistoryStore.shared.items)
    }

    /// Recompute the sorted + filtered list only when the store contents or
    /// search query changed. A cheap identity check short-circuits the expensive
    /// O(n log n) sort when nothing changed (e.g. a pure re-render triggered by
    /// an unrelated state change). Catches content-only mutations (pin toggle,
    /// dedup reorder) that a plain count check would miss.
    func refreshDisplayedItems(from store: [ClipboardItem]) {
        let effective = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.count == lastStoreCount,
           effective == lastQuery,
           store == lastItems {
            return
        }
        cachedDisplayedItems = displayedItems(from: store)
        lastItems = store
        lastStoreCount = store.count
        lastQuery = effective
    }

    /// Pinned first, then by recency (store order), optionally filtered.
    /// `query` overrides the view model's own searchText (used by the quick panel).
    ///
    /// - Note: The main history view consumes `cachedDisplayedItems` (kept fresh
    ///   via `refreshDisplayedItems`). This method is retained for internal cache
    ///   recomputation and for the quick panel, which passes its own `query`.
    func displayedItems(from items: [ClipboardItem], query: String? = nil) -> [ClipboardItem] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastCopiedAt > rhs.lastCopiedAt
        }
        let effective = (query ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !effective.isEmpty else { return sorted }
        let lower = effective.lowercased()
        return sorted.filter { item in
            if let text = item.text, text.lowercased().contains(lower) { return true }
            if let urls = item.fileURLs,
               urls.contains(where: { $0.lastPathComponent.lowercased().contains(lower) }) { return true }
            if let link = item.linkURL, link.absoluteString.lowercased().contains(lower) { return true }
            return false
        }
    }

    func copyBack(_ item: ClipboardItem) {
        ClipboardHistoryStore.shared.copyBackToPasteboard(item)
        feedbackTask?.cancel()
        lastCopiedID = item.id
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            self.lastCopiedID = nil
        }
    }

    /// URLs Quick Look can preview: file references or the stored image blob.
    func quickLookURLs(for item: ClipboardItem) -> [URL] {
        if let urls = item.fileURLs, !urls.isEmpty {
            return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        if let blob = ClipboardHistoryStore.shared.blobURL(for: item) {
            return [blob]
        }
        return []
    }
}
