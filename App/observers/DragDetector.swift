//
//  DragDetector.swift
//  DropNest
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
import UniformTypeIdentifiers

/// 全局鼠标监视器只会在主线程 runloop 上派发，因此整体标注为 @MainActor：
/// 回调方可以直接同步调用主线程隔离的对象（如 ShakeGestureDetector），
/// 避免拖拽期间（60~120Hz）为每个事件额外分配一个 Task 并产生时序抖动。
///
/// 单例化：多显示器环境下只创建一组 NSEvent global monitor（而非每屏一组），
/// 内部维护 [UUID: CGRect] 热区字典，一次事件判断所有屏幕区域。
/// 避免多屏时每次鼠标移动被系统派发 N 遍闭包。
@MainActor
final class DragDetector {

    static let shared = DragDetector()

    // MARK: - Callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    /// 拖拽进入某屏幕刘海区域时触发，参数为该屏幕 UUID
    var onDragEntersNotchRegion: ((_ screenUUID: String) -> Void)?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?
    /// 拖拽结束（leftMouseUp）回调，供摇晃检测器等重置采样
    var onDragEnd: VoidCallback?
    /// v2.1：检测到内容拖拽开始（drag pasteboard 出现有效内容）时触发——驱动巢群显示
    var onContentDragStart: PositionCallback?
    /// v2.1：内容拖拽结束（leftMouseUp）时触发——驱动空巢胚清理
    var onContentDragEnd: VoidCallback?

    // 监视器令牌需要在 deinit（nonisolated 上下文）中释放，故标为 nonisolated(unsafe)；
    // 实际读写均发生在主线程（startMonitoring / stopMonitoring / deinit），不存在竞争
    private nonisolated(unsafe) var mouseDownMonitor: Any?
    private nonisolated(unsafe) var mouseDraggedMonitor: Any?
    private nonisolated(unsafe) var mouseUpMonitor: Any?

    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    /// 已进入刘海区域的屏幕 UUID（同时只可能在一块屏幕的刘海区域内）
    private var enteredScreenUUID: String?

    /// 多屏刘海热区字典：UUID -> notchRegion。
    /// 替代原来每屏一个 DragDetector 实例的 notchRegion 字段。
    private var notchRegions: [String: CGRect] = [:]

    private let dragPasteboard = NSPasteboard(name: .drag)

    private init() {}

    // MARK: - Region management

    /// 更新所有屏幕的刘海热区。每次屏幕配置变化或重新设置 detector 时调用。
    func updateNotchRegions(_ regions: [String: CGRect]) {
        notchRegions = regions
        enteredScreenUUID = nil
    }

    // MARK: - Private Helpers

    /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent() -> Bool {
        let validTypes: [NSPasteboard.PasteboardType] = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string
        ]
        return dragPasteboard.types?.contains(where: validTypes.contains) ?? false
    }

    func startMonitoring() {
        stopMonitoring()

        // Track pasteboard to detect content drag
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            // NSEvent global monitor handler 是 @Sendable 闭包（nonisolated），但回调在主线程 RunLoop 派发。
            // MainActor.assumeIsolated 向编译器声明隔离，零运行时开销，避免高频拖拽事件分配 Task。
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.pasteboardChangeCount = self.dragPasteboard.changeCount
                self.isDragging = true
                self.isContentDragging = false
                self.enteredScreenUUID = nil
            }
        }

        // Track drag movement and notch region intersection
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                guard self.isDragging else { return }

                let mouseLocation = NSEvent.mouseLocation
                let newContent = self.dragPasteboard.changeCount != self.pasteboardChangeCount

                // Detect if actual content is being dragged AND it's valid content
                if newContent && !self.isContentDragging && self.hasValidDragContent() {
                    self.isContentDragging = true
                    // v2.1：内容拖拽开始 → 通知巢群管理器创建空巢胚
                    self.onContentDragStart?(mouseLocation)
                }

                // Only process position when content is being dragged
                if self.isContentDragging {
                    self.onDragMove?(mouseLocation)

                    // Track notch region entry/exit across all screens
                    let hitUUID = self.notchRegionHit(by: mouseLocation)
                    if let hit = hitUUID, self.enteredScreenUUID != hit {
                        self.enteredScreenUUID = hit
                        self.onDragEntersNotchRegion?(hit)
                    } else if hitUUID == nil && self.enteredScreenUUID != nil {
                        self.enteredScreenUUID = nil
                        self.onDragExitsNotchRegion?()
                    }
                }
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                guard self.isDragging else { return }

                let wasContentDragging = self.isContentDragging
                self.isDragging = false
                self.isContentDragging = false
                self.enteredScreenUUID = nil
                self.pasteboardChangeCount = -1
                self.onDragEnd?()
                // v2.1：内容拖拽结束 → 通知巢群管理器清理空巢胚
                if wasContentDragging {
                    self.onContentDragEnd?()
                }
            }
        }
    }

    /// 返回鼠标所在刘海区域的屏幕 UUID（同时只可能命中一块屏幕）
    private func notchRegionHit(by point: CGPoint) -> String? {
        for (uuid, region) in notchRegions where region.contains(point) {
            return uuid
        }
        return nil
    }

    func stopMonitoring() {
        removeMonitors()
        isDragging = false
        isContentDragging = false
        enteredScreenUUID = nil
    }

    /// 仅摘除事件监视器，不触碰主线程隔离状态，便于 deinit 复用
    private nonisolated func removeMonitors() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
    }

    deinit {
        removeMonitors()
    }
}
