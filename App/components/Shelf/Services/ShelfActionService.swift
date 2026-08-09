//
//  ShelfActionService.swift
//  DropNest
//
//  Created by Alexander on 2025-10-07.
//

import AppKit
import Foundation

/// A service providing common actions for `ShelfItem`s, such as opening, revealing, or copying paths.
@MainActor
enum ShelfActionService {

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .file(let bookmark):
            handleBookmarkedFile(bookmark) { url in
                NSWorkspace.shared.open(url)
            }
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }

    static func reveal(_ item: ShelfItem) {
        guard case .file(let bookmark) = item.kind else { return }
        handleBookmarkedFile(bookmark) { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copyPath(_ item: ShelfItem) {
        guard case .file(let bookmark) = item.kind else { return }
        handleBookmarkedFile(bookmark) { url in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }

    static func remove(_ item: ShelfItem) {
        ShelfStateViewModel.shared.remove(item)
    }

    private static func handleBookmarkedFile(_ bookmarkData: Data, action: @escaping @Sendable (URL) -> Void) {
        // Task.detached 确保 bookmark.resolveURL() 在后台线程执行，不阻塞主线程。
        // 之前用结构化 Task 继承 @MainActor，导致 resolve 在主线程同步执行。
        Task.detached(priority: .userInitiated) {
            let bookmark = Bookmark(data: bookmarkData)
            guard let url = bookmark.resolveURL() else { return }
            url.accessSecurityScopedResource { accessibleURL in
                action(accessibleURL)
            }
        }
    }
}

