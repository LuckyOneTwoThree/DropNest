import XCTest
@testable import DropNest

/// ShelfItem Codable 回归测试（#3 Shelf 持久化）。
///
/// ShelfPersistenceService 已把 encode+write 移到后台线程（800ms 防抖），
/// 编解码一致性是持久化 round-trip 的基础。此处验证各 kind 经 JSON 序列化后
/// 能完整还原，避免后台编码引入的字段丢失/类型漂移。
///
/// 仅测纯值类型，不触碰 ShelfPersistenceService 单例磁盘文件。
final class ShelfItemCodableTests: XCTestCase {

    private func roundTrip(_ item: ShelfItem) throws -> ShelfItem {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ShelfItem.self, from: data)
    }

    /// text kind round-trip：字符串内容与 id 保持一致。
    func testTextKindRoundTrip() throws {
        let id = UUID()
        let item = ShelfItem(id: id, kind: .text(string: "hello shelf"))
        let decoded = try roundTrip(item)
        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.id, id)
        if case .text(let s) = decoded.kind {
            XCTAssertEqual(s, "hello shelf")
        } else {
            XCTFail("kind 应仍为 text")
        }
    }

    /// link kind round-trip。
    func testLinkKindRoundTrip() throws {
        let url = URL(string: "https://example.com/path")!
        let item = ShelfItem(kind: .link(url: url))
        let decoded = try roundTrip(item)
        XCTAssertEqual(decoded, item)
        if case .link(let decodedURL) = decoded.kind {
            XCTAssertEqual(decodedURL, url)
        } else {
            XCTFail("kind 应仍为 link")
        }
    }

    /// file kind round-trip：bookmark Data 完整保留。
    func testFileKindRoundTrip() throws {
        let bookmark = Data(repeating: 0xAB, count: 32)
        let item = ShelfItem(kind: .file(bookmark: bookmark))
        let decoded = try roundTrip(item)
        XCTAssertEqual(decoded, item)
        if case .file(let decodedBookmark) = decoded.kind {
            XCTAssertEqual(decodedBookmark, bookmark)
        } else {
            XCTFail("kind 应仍为 file")
        }
    }

    /// groupID / isTemporary 元数据 round-trip 保留（集合巢群依赖 groupID 持久化）。
    func testGroupMetadataRoundTrip() throws {
        let groupID = UUID()
        let item = ShelfItem(kind: .text(string: "grouped"), isTemporary: true, groupID: groupID)
        let decoded = try roundTrip(item)
        XCTAssertEqual(decoded.groupID, groupID)
        XCTAssertTrue(decoded.isTemporary)
    }

    /// 数组 round-trip：模拟 items.json 的真实形态，验证顺序与去重 id 保留。
    func testArrayRoundTrip() throws {
        let items = [
            ShelfItem(kind: .text(string: "a")),
            ShelfItem(kind: .link(url: URL(string: "https://b.com")!)),
            ShelfItem(kind: .text(string: "c"))
        ]
        let encoder = JSONEncoder()
        let data = try encoder.encode(items)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([ShelfItem].self, from: data)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded, items)
    }
}
