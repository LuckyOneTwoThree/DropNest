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
@MainActor
final class DragDetector {

    // MARK: - Callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onDragEntersNotchRegion: VoidCallback?
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
    private var hasEnteredNotchRegion: Bool = false

    private let notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
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
            guard let self = self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
        }

        // Track drag movement and notch region intersection
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
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

                // Track notch region entry/exit
                let containsMouse = self.notchRegion.contains(mouseLocation)
                if containsMouse && !self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = true
                    self.onDragEntersNotchRegion?()
                } else if !containsMouse && self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = false
                    self.onDragExitsNotchRegion?()
                }
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }

            let wasContentDragging = self.isContentDragging
            self.isDragging = false
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.pasteboardChangeCount = -1
            self.onDragEnd?()
            // v2.1：内容拖拽结束 → 通知巢群管理器清理空巢胚
            if wasContentDragging {
                self.onContentDragEnd?()
            }
        }
    }

    func stopMonitoring() {
        removeMonitors()
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
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
