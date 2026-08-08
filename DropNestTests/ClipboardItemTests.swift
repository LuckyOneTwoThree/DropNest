import XCTest
@testable import DropNest

/// ClipboardItem 纯逻辑回归测试。
///
/// 覆盖代码审查报告中的：
/// - #5 剪贴板去重哈希：`makeHash` 在后台线程计算，其正确性是去重置顶的基础。
/// - #7 置顶/大载荷治理：RTF/HTML/图片落盘为 blob，只存文件名——验证 blob 字段
///   Codable round-trip 不回归（旧版把 RTF/HTML base64 内联 items.json 常驻内存）。
///
/// 仅测纯值类型，不触碰 ClipboardHistoryStore 单例与磁盘 IO。
final class ClipboardItemTests: XCTestCase {

    // MARK: - makeHash（#5 去重哈希）

    /// 相同文本内容应产生相同哈希（去重置顶的前提）。
    func testMakeHashSameTextIsEqual() {
        let h1 = ClipboardItem.makeHash(text: "hello")
        let h2 = ClipboardItem.makeHash(text: "hello")
        XCTAssertEqual(h1, h2, "相同文本必须产生相同 contentHash，否则去重失效")
    }

    /// 不同文本应产生不同哈希。
    func testMakeHashDifferentTextDiffers() {
        let h1 = ClipboardItem.makeHash(text: "hello")
        let h2 = ClipboardItem.makeHash(text: "world")
        XCTAssertNotEqual(h1, h2)
    }

    /// 哈希为 SHA-256 hex（64 位小写十六进制）。
    func testMakeHashIsSHA256Hex() {
        let h = ClipboardItem.makeHash(text: "abc")
        XCTAssertEqual(h.count, 64, "SHA-256 hex 应为 64 个字符")
        XCTAssertTrue(h.allSatisfy { $0.isHexDigit }, "应仅含十六进制字符")
    }

    /// fileURLs 哈希应与路径顺序无关（内部 sorted），同一组文件的不同拖入顺序视作同内容。
    func testMakeHashFileURLsOrderIndependent() {
        let u1 = URL(fileURLWithPath: "/tmp/a.txt")
        let u2 = URL(fileURLWithPath: "/tmp/b.txt")
        let h1 = ClipboardItem.makeHash(fileURLs: [u1, u2])
        let h2 = ClipboardItem.makeHash(fileURLs: [u2, u1])
        XCTAssertEqual(h1, h2, "文件哈希应与输入顺序无关")
    }

    /// 不同类别载荷应产生不同哈希：相同字符串作为 text 与作为 link 不应碰撞。
    func testMakeHashDifferentKindsDontCollide() {
        let textHash = ClipboardItem.makeHash(text: "https://example.com")
        let linkHash = ClipboardItem.makeHash(linkURL: URL(string: "https://example.com")!)
        XCTAssertNotEqual(textHash, linkHash, "text:// 与 link:// 前缀应避免跨类别碰撞")
    }

    /// image 哈希基于像素数据：相同数据同哈希，不同数据不同哈希。
    func testMakeHashImageData() {
        let d1 = Data([0x00, 0x01, 0x02])
        let d2 = Data([0x00, 0x01, 0x03])
        XCTAssertEqual(ClipboardItem.makeHash(imageData: d1), ClipboardItem.makeHash(imageData: d1))
        XCTAssertNotEqual(ClipboardItem.makeHash(imageData: d1), ClipboardItem.makeHash(imageData: d2))
    }

    // MARK: - Codable round-trip（#7 blob 字段治理）

    /// RTF/HTML/图片落盘为 blob 后，ClipboardItem 只存 blob 文件名。
    /// 验证三个 blobName 字段经 JSON round-trip 仍保持一致，且 rtfData/htmlData 为 nil
    /// （新条目不应再把大载荷内联进 JSON 常驻内存）。
    func testBlobFieldsCodableRoundTrip() throws {
        let item = ClipboardItem(
            text: "sample",
            imageBlobName: "uuid-1.png",
            rtfBlobName: "uuid-2.rtf",
            htmlBlobName: "uuid-3.html",
            fileURLs: nil,
            linkURL: nil,
            sourceAppBundleID: "com.test.app",
            contentHash: ClipboardItem.makeHash(text: "sample")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ClipboardItem.self, from: data)

        XCTAssertEqual(decoded.imageBlobName, "uuid-1.png")
        XCTAssertEqual(decoded.rtfBlobName, "uuid-2.rtf")
        XCTAssertEqual(decoded.htmlBlobName, "uuid-3.html")
        XCTAssertNil(decoded.rtfData, "新条目 rtfData 应为 nil（落盘为 blob）")
        XCTAssertNil(decoded.htmlData, "新条目 htmlData 应为 nil（落盘为 blob）")
        XCTAssertEqual(decoded.contentHash, item.contentHash)
        XCTAssertEqual(decoded.text, "sample")
    }

    /// primaryKind 优先级：file > image > link > text。
    func testPrimaryKindPrecedence() {
        XCTAssertEqual(
            ClipboardItem(text: "x", contentHash: "h").primaryKind,
            .text
        )
        XCTAssertEqual(
            ClipboardItem(linkURL: URL(string: "https://e.com")!, contentHash: "h").primaryKind,
            .link
        )
        // image 优先于 link/text
        XCTAssertEqual(
            ClipboardItem(imageBlobName: "i.png", contentHash: "h").primaryKind,
            .image
        )
        // file 优先于 image/link/text
        XCTAssertEqual(
            ClipboardItem(fileURLs: [URL(fileURLWithPath: "/tmp/f")], contentHash: "h").primaryKind,
            .file
        )
    }
}

private extension Character {
    var isHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
