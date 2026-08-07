//
//  ClipboardItem.swift
//  DropNest
//
//  Created on 2026-08-07.
//  Clipboard history data model. See .workbuddy/plans/2026-08-07-clipboard-history-plan.md
//

import AppKit
import CryptoKit
import Foundation

enum ClipboardItemKind: String, Codable, Sendable {
    case text
    case image
    case file
    case link

    var iconSymbolName: String {
        switch self {
        case .text: return "text.justifyleft"
        case .image: return "photo"
        case .file: return "doc"
        case .link: return "link"
        }
    }
}

/// A single clipboard history entry. One copy action may carry multiple
/// representations (plain text + RTF + HTML, image, file URLs) — all are
/// stored and written back together on re-copy so pasting behaves identically
/// to the original copy.
@MainActor
struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var firstCopiedAt: Date
    var lastCopiedAt: Date
    var copyCount: Int

    // Multi-type payload
    var text: String?
    var rtfData: Data?
    var htmlData: Data?
    /// File name inside ClipboardHistory/blobs/ (PNG). Binary stays out of JSON.
    var imageBlobName: String?
    /// Finder file references — URL only, content is never copied.
    var fileURLs: [URL]?
    var linkURL: URL?

    var sourceAppBundleID: String?
    /// Stable dedup key: SHA-256 hex of the primary payload (see `makeHash`).
    var contentHash: String
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        firstCopiedAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        copyCount: Int = 1,
        text: String? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imageBlobName: String? = nil,
        fileURLs: [URL]? = nil,
        linkURL: URL? = nil,
        sourceAppBundleID: String? = nil,
        contentHash: String,
        isPinned: Bool = false
    ) {
        self.id = id
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.text = text
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageBlobName = imageBlobName
        self.fileURLs = fileURLs
        self.linkURL = linkURL
        self.sourceAppBundleID = sourceAppBundleID
        self.contentHash = contentHash
        self.isPinned = isPinned
    }

    /// Display category. Precedence: file > image > link > text.
    var primaryKind: ClipboardItemKind {
        if let urls = fileURLs, !urls.isEmpty { return .file }
        if imageBlobName != nil { return .image }
        if linkURL != nil { return .link }
        return .text
    }

    var previewTitle: String {
        switch primaryKind {
        case .file:
            let urls = fileURLs ?? []
            guard let first = urls.first else { return "文件" }
            let name = (try? first.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? first.lastPathComponent
            return urls.count > 1 ? "\(name) 等 \(urls.count) 项" : name
        case .image:
            return "图片"
        case .link:
            guard let url = linkURL else { return "" }
            let s = url.absoluteString
            if s.hasPrefix("https://") { return String(s.dropFirst("https://".count)) }
            if s.hasPrefix("http://") { return String(s.dropFirst("http://".count)) }
            return s
        case .text:
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
            return firstLine.count > 80 ? String(firstLine.prefix(77)) + "..." : firstLine
        }
    }

    /// File items whose source has been moved or deleted are shown greyed out.
    var isSourceMissing: Bool {
        guard let urls = fileURLs, !urls.isEmpty else { return false }
        return urls.contains { !FileManager.default.fileExists(atPath: $0.path) }
    }

    var sourceAppIcon: NSImage? {
        guard let bundleID = sourceAppBundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

// MARK: - Dedup hashing
extension ClipboardItem {
    /// SHA-256 hex of the primary payload. Text/link hash the string, images
    /// hash the PNG data, files hash the joined standardized paths.
    static func makeHash(text: String? = nil, imageData: Data? = nil, fileURLs: [URL]? = nil, linkURL: URL? = nil) -> String {
        if let urls = fileURLs, !urls.isEmpty {
            let joined = urls.map { $0.standardizedFileURL.path }.sorted().joined(separator: "\n")
            return sha256Hex(Data(("files://" + joined).utf8))
        }
        if let imageData = imageData {
            return sha256Hex(imageData)
        }
        if let url = linkURL {
            return sha256Hex(Data(("link://" + url.absoluteString).utf8))
        }
        return sha256Hex(Data(("text://" + (text ?? "")).utf8))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
