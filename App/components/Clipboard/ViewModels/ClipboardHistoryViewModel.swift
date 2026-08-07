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

    @Published var searchText: String = ""
    /// Brief "已复制" visual feedback target after tapping an item.
    @Published var lastCopiedID: UUID?

    private var feedbackTask: Task<Void, Never>?

    private init() {}

    /// Pinned first, then by recency (store order), optionally filtered.
    /// `query` overrides the view model's own searchText (used by the quick panel).
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
