import XCTest
@testable import DropNest

/// ShelfStateViewModel 核心逻辑单元测试。
///
/// 覆盖：去重 add、成组 createGroup、解散 dissolveGroup、删除组 deleteGroup、单条移除 remove。
/// 仅测纯逻辑，不依赖 ShelfPersistenceService 的文件 IO（条目均用 text kind，
/// `cleanupStoredData` 对非 file 条目是空操作；`FloatingNestManager` 在无面板时也是空操作）。
///
/// 注意：ShelfStateViewModel 是 @MainActor 单例，故测试类与 setUp 均标注 @MainActor。
/// 用 `@testable import DropNest` 访问 internal 类型；模块名非 DropNest 时请改为实际 PRODUCT_MODULE_NAME。
@MainActor
final class ShelfStateViewModelTests: XCTestCase {

    private var vm: ShelfStateViewModel { .shared }

    override func setUp() async throws {
        try await super.setUp()
        // 单例状态会在用例间泄漏，每个用例开始前重置为空，避免依赖持久化文件内容。
        vm.clearAll()
    }

    /// 构造一个纯文本条目（绕开 file/bookmark 相关 IO）。
    private func makeTextItem(_ text: String, id: UUID = UUID()) -> ShelfItem {
        ShelfItem(kind: .text(string: text), id: id)
    }

    // MARK: - add

    /// 重复内容（identityKey 相同）的条目应按 identityKey 去重，且保留先存在的条目。
    func testAddItemsDeduplicates() {
        let idA = UUID()
        let a = makeTextItem("hello", id: idA)
        vm.add([a])
        XCTAssertEqual(vm.items.count, 1)

        // 同内容、不同 id → 视为重复
        let aDup = makeTextItem("hello", id: UUID())
        vm.add([aDup])

        XCTAssertEqual(vm.items.count, 1, "按 identityKey 去重，重复条目不应增加计数")
        XCTAssertEqual(vm.items.first?.id, idA, "去重应保留先存在的条目")
    }

    // MARK: - createGroup

    /// createGroup 应给指定条目赋同一 groupID，未入选条目保持独立。
    func testCreateGroupAssignsGroupID() {
        let i1 = makeTextItem("one")
        let i2 = makeTextItem("two")
        let i3 = makeTextItem("three")
        vm.add([i1, i2, i3])

        let groupID = vm.createGroup(from: [i1.id, i3.id])

        let members = vm.items(inGroup: groupID)
        XCTAssertEqual(members.count, 2, "组内应恰好包含被选中的 2 个条目")
        XCTAssertEqual(Set(members.map { $0.id }), Set([i1.id, i3.id]))
        XCTAssertNil(vm.items.first { $0.id == i2.id }?.groupID,
                     "未入选条目 groupID 应保持 nil")
    }

    // MARK: - dissolveGroup

    /// dissolveGroup 应清除组内条目的 groupID，但条目本身仍保留在文件架中。
    func testDissolveGroupClearsGroupID() {
        let i1 = makeTextItem("one")
        let i2 = makeTextItem("two")
        vm.add([i1, i2])
        let groupID = vm.createGroup(from: [i1.id, i2.id])
        XCTAssertEqual(vm.items(inGroup: groupID).count, 2)

        vm.dissolveGroup(groupID)

        XCTAssertTrue(vm.items(inGroup: groupID).isEmpty, "解散后该组应无条目")
        for item in vm.items {
            XCTAssertNil(item.groupID, "解散后所有条目 groupID 应为 nil")
        }
        XCTAssertEqual(vm.items.count, 2, "解散不应移除条目本身")
    }

    // MARK: - deleteGroup

    /// deleteGroup 应移除组内全部条目，独立条目不受影响。
    func testDeleteGroupRemovesItems() {
        let i1 = makeTextItem("one")
        let i2 = makeTextItem("two")
        let i3 = makeTextItem("three")
        vm.add([i1, i2, i3])
        let groupID = vm.createGroup(from: [i1.id, i2.id])

        vm.deleteGroup(groupID)

        XCTAssertEqual(vm.items.count, 1, "组内条目应被全部移除，仅剩独立条目")
        XCTAssertEqual(vm.items.first?.id, i3.id)
    }

    // MARK: - remove

    /// remove 应移除指定条目。
    func testRemoveItem() {
        let i1 = makeTextItem("one")
        let i2 = makeTextItem("two")
        vm.add([i1, i2])
        XCTAssertEqual(vm.items.count, 2)

        vm.remove(i1)

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.id, i2.id)
    }
}
