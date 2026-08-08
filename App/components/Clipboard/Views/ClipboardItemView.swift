//
//  ClipboardItemView.swift
//  DropNest
//
//  Created on 2026-08-07.
//

import SwiftUI

struct ClipboardItemView: View {
    let item: ClipboardItem
    let onCopy: () -> Void

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
                        if let icon = item.sourceAppIcon {
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
                            Text("源已失效")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                if isCurrentClipboard {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("当前剪贴板内容")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(item.isSourceMissing ? 0.5 : 1)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch item.primaryKind {
        case .image:
            if let url = ClipboardHistoryStore.shared.blobURL(for: item),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .help("点击行复制 · 右键快速查看大图")
            } else {
                symbolThumb("photo")
            }
        case .file:
            if let first = item.fileURLs?.first,
               FileManager.default.fileExists(atPath: first.path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
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
