//
//  ClipboardItemView.swift
//  DropNest
//
//  Created on 2026-08-07.
//

import SwiftUI
import ImageIO

/// ImageIO 下采样：只解码到目标像素尺寸，避免把整张 PNG（可达 10MB）
/// 全量解码成位图常驻内存。28pt 行高 ×2（Retina）≈ 56px，取 64 留余量。
private nonisolated func downsampledThumbnail(at url: URL, maxPixelSize: Int = 64) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    let onCopy: () -> Void

    /// Decoded image / file-type icon, loaded once off the main thread per item.
    @State private var cachedThumbnail: NSImage?
    /// Source-app icon resolved from `sourceAppBundleID`, loaded async.
    @State private var cachedAppIcon: NSImage?

    /// True when this row matches the content currently on the system pasteboard.
    private var isCurrentClipboard: Bool {
        guard let hash = ClipboardHistoryStore.shared.currentContentHash else { return false }
        return hash == item.contentHash
    }

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 10) {
                thumbnail
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Text(item.previewTitle)
                            .font(.system(.callout, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 4) {
                        if let icon = cachedAppIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 12, height: 12)
                        }
                        Text(item.lastCopiedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if item.copyCount > 1 {
                            Text("×\(item.copyCount)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if item.isSourceMissing {
                            Text("Source Expired")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                if isCurrentClipboard {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Current Clipboard Content")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.isSourceMissing ? 0.5 : 1)
        .task(id: item.id) {
            await loadCachedAssets()
        }
    }

    /// Loads the thumbnail and source-app icon off the main thread so the row
    /// body never blocks on disk decode or `NSWorkspace.icon` lookups. Runs once
    /// per `item.id`; results are cached in `@State` for subsequent renders.
    @MainActor
    private func loadCachedAssets() async {
        let kind = item.primaryKind

        // Thumbnail: image blob decode or file type icon.
        switch kind {
        case .image:
            if let url = ClipboardHistoryStore.shared.blobURL(for: item) {
                let image = await Task.detached(priority: .userInitiated) { downsampledThumbnail(at: url) }.value
                if !Task.isCancelled { cachedThumbnail = image }
            }
        case .file:
            if let first = item.fileURLs?.first,
               FileManager.default.fileExists(atPath: first.path) {
                let path = first.path
                let icon = await Task.detached(priority: .userInitiated) { NSWorkspace.shared.icon(forFile: path) }.value
                if !Task.isCancelled { cachedThumbnail = icon }
            }
        case .link, .text:
            break
        }

        // Source-app icon: resolve bundle → app URL → icon off the main thread.
        if let bundleID = item.sourceAppBundleID {
            let icon = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
                return NSWorkspace.shared.icon(forFile: appURL.path)
            }.value
            if !Task.isCancelled { cachedAppIcon = icon }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.primaryKind {
        case .image:
            if let image = cachedThumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .help("Click row to copy · Right click to preview image")
            } else {
                symbolThumb("photo")
            }
        case .file:
            if let image = cachedThumbnail {
                Image(nsImage: image)
                    .resizable()
            } else {
                symbolThumb("doc.questionmark")
            }
        case .link:
            symbolThumb(item.primaryKind.iconSymbolName)
        case .text:
            symbolThumb(item.primaryKind.iconSymbolName)
        }
    }

    private func symbolThumb(_ name: String) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.white.opacity(0.08))
            .overlay {
                Image(systemName: name)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
    }
}
