//
//  ClipboardMonitor.swift
//  DropNest
//
//  Created on 2026-08-07.
//  Polls NSPasteboard.general.changeCount (Maccy-style) and hands validated
//  captures to ClipboardHistoryStore.
//

import AppKit
import Defaults
import Foundation

/// Raw payload extracted from one pasteboard change, before dedup/storage.
struct CapturedContent: Sendable {
    var text: String?
    var rtfData: Data?
    var htmlData: Data?
    var imageData: Data?
    /// 未转换的 TIFF 原始数据——转换（TIFF→PNG）是重活，推迟到后台线程执行
    var tiffData: Data?
    var fileURLs: [URL]?
    var linkURL: URL?
    var sourceAppBundleID: String?
}

@MainActor
final class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int
    private var enabledObservation: Defaults.Observation?

    /// Poll interval. 500 ms matches Maccy — negligible CPU, rare misses.
    private let pollInterval: TimeInterval = 0.5

    private init() {
        lastChangeCount = pasteboard.changeCount
        observeEnabled()
    }

    // MARK: - Lifecycle

    private func observeEnabled() {
        enabledObservation = Defaults.observe(.clipboardHistoryEnabled) { [weak self] change in
            Task { @MainActor in
                if change.newValue { self?.start() } else { self?.stop() }
            }
        }
        if Defaults[.clipboardHistoryEnabled] { start() }
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called by the store after it writes an item back to the pasteboard,
    /// so our own write is not captured as a new history entry.
    func syncAfterSelfWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Polling

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard ClipboardFilter.shouldCapture(pasteboard, sourceAppBundleID: sourceApp) else { return }

        let capture = extract(from: pasteboard, sourceAppBundleID: sourceApp)
        guard capture != nil else { return }
        ClipboardHistoryStore.shared.insert(capture!)
    }

    // MARK: - Extraction

    private func extract(from pb: NSPasteboard, sourceAppBundleID: String?) -> CapturedContent? {
        var content = CapturedContent(sourceAppBundleID: sourceAppBundleID)

        // File references (Finder copy). URL only — content is never read.
        if Defaults[.clipboardKeepFiles],
           let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            content.fileURLs = urls
        }

        // Image: prefer PNG; TIFF is kept raw and converted to PNG off the
        // main thread by the store (NSBitmapImageRep conversion is expensive).
        if Defaults[.clipboardKeepImages] {
            if let png = pb.data(forType: .png) {
                content.imageData = png
            } else if let tiff = pb.data(forType: .tiff) {
                content.tiffData = tiff
            }
        }

        // Link (browser drags/copies). Skip file:// — already covered above.
        if let urlString = pb.string(forType: NSPasteboard.PasteboardType("public.url")),
           let url = URL(string: urlString), !url.isFileURL {
            content.linkURL = url
        }

        // Text + rich representations.
        content.text = pb.string(forType: .string)
        content.rtfData = pb.data(forType: .rtf)
        content.htmlData = pb.data(forType: .html)

        // Drop empty captures (e.g. types we don't model).
        if content.text == nil && content.imageData == nil && content.tiffData == nil
            && content.fileURLs == nil && content.linkURL == nil {
            return nil
        }

        guard ClipboardFilter.withinSizeLimit(
            imageData: content.imageData ?? content.tiffData,
            rtfData: content.rtfData,
            htmlData: content.htmlData,
            text: content.text
        ) else {
            print("📋 Clipboard item exceeds size limit, skipped")
            return nil
        }

        return content
    }
}
