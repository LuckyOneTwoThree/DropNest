//
//  NestGroupCardView.swift
//  DropNest
//
//  集合（巢群）卡片：叠层缩略图 + 数量角标 + 组名。
//  点击就地展开/收起查看组内条目；整体拖出 = 组内全部条目写入同一 drag session。
//

import AppKit
import SwiftUI
import Defaults

struct NestGroupCardView: View {
    let groupID: UUID
    let members: [ShelfItem]
    let name: String

    @StateObject private var tvm = ShelfStateViewModel.shared
    @State private var thumbnails: [NSImage] = []
    @State private var cachedPreviewImage: NSImage?

    private var isExpanded: Bool { tvm.expandedGroupIDs.contains(groupID) }

    /// 卡片上叠层展示的缩略图（前 3 项，加载完成前回退到类型图标）
    private var displayImages: [NSImage] {
        Array(members.prefix(3)).enumerated().map { index, item in
            index < thumbnails.count ? thumbnails[index] : item.icon
        }
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedContent
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else {
                collapsedCard
                    .transition(.scale(scale: 1.08).combined(with: .opacity))
            }
        }
        .animation(.nestSpring, value: isExpanded)
        .task(id: members) {
            await loadThumbnails()
            if cachedPreviewImage == nil {
                cachedPreviewImage = renderDragPreview()
            }
        }
    }

    // MARK: - Collapsed card

    private var collapsedCard: some View {
        ZStack {
            VStack(alignment: .center, spacing: 6) {
                stackedIconView
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 90, height: 14, alignment: .center)
            }
            .frame(width: 105)
            .padding(.vertical, 12)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .overlay(alignment: .topTrailing) { countBadge }

            GroupCardDragHandler(
                groupID: groupID,
                members: members,
                previewImage: cachedPreviewImage ?? displayImages.first
            )
        }
        .help("\(name) · \(members.count) 项，点击以悬浮巢展示")
    }

    /// 精炼叠层图标：扇形展开，最前层最大，后方逐层缩窄偏移
    private var stackedIconView: some View {
        let images = displayImages
        return ZStack {
            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
                    .offset(
                        x: CGFloat(index) * 4 - CGFloat(images.count - 1) * 2,
                        y: -CGFloat(index) * 3
                    )
                    .zIndex(Double(index))
            }
        }
        .frame(width: 56, height: 56)
    }

    /// 胶囊式数量角标（完全在卡片内部，不向外偏移避免被裁剪）
    private var countBadge: some View {
        Text("\(members.count)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
            .padding(6) // 向内留 6pt 边距，确保角标不被裁剪
    }

    // MARK: - Expanded content（就地展开组内条目）

    private var expandedContent: some View {
        HStack(spacing: 6) {
            Button {
                tvm.toggleGroupExpanded(groupID)
            } label: {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("收起查看")

            ForEach(members) { item in
                ShelfItemView(item: item)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [5])
                        )
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    // MARK: - Thumbnails & drag preview

    private func loadThumbnails() async {
        var images: [NSImage] = []
        for item in members.prefix(3) {
            guard !Task.isCancelled else { return }
            if let url = item.fileURL,
               let image = await ThumbnailService.shared.thumbnail(for: url, size: CGSize(width: 48, height: 48)) {
                images.append(image)
            } else {
                images.append(item.icon)
            }
        }
        guard !Task.isCancelled else { return }
        thumbnails = images
    }

    private func renderDragPreview() -> NSImage {
        let content = DragPreviewView(
            thumbnail: displayImages.first ?? members.first?.icon,
            displayName: "\(name)（\(members.count) 项）"
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.nsImage ?? members.first?.icon ?? NSImage()
    }
}

// MARK: - 卡片交互（点击展开 / 右键菜单 / 整体拖出）

private struct GroupCardDragHandler: NSViewRepresentable {
    let groupID: UUID
    let members: [ShelfItem]
    let previewImage: NSImage?

    func makeNSView(context: Context) -> GroupCardDragView {
        let view = GroupCardDragView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: GroupCardDragView, context: Context) {
        update(nsView)
    }

    private func update(_ view: GroupCardDragView) {
        view.groupID = groupID
        view.members = members
        view.dragPreviewImage = previewImage
    }

    final class GroupCardDragView: NSView, NSDraggingSource {
        var groupID: UUID!
        var members: [ShelfItem] = []
        var dragPreviewImage: NSImage?

        private var mouseDownEvent: NSEvent?
        private var didDrag = false
        private let dragThreshold: CGFloat = 3.0
        private var draggedURLs: [URL] = []

        override func rightMouseDown(with event: NSEvent) {
            presentContextMenu(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownEvent else {
                super.mouseDragged(with: event)
                return
            }
            let dragDistance = hypot(
                event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
                event.locationInWindow.y - mouseDownEvent.locationInWindow.y
            )
            if dragDistance > dragThreshold {
                didDrag = true
                self.mouseDownEvent = nil
                startDragSession(with: event)
            } else {
                super.mouseDragged(with: event)
            }
        }

        override func mouseUp(with event: NSEvent) {
            if !didDrag && event.clickCount == 1 {
                // v2.1：点击组卡片 → 以悬浮巢形式展示在桌面（调 FloatingNestManager.toggle）
                FloatingNestManager.shared.toggle(groupID: groupID)
            }
            mouseDownEvent = nil
        }

        // MARK: 整体拖出

        private func startDragSession(with event: NSEvent) {
            var draggingItems: [NSDraggingItem] = []
            for member in members {
                guard let pasteboardItem = ShelfDragPayloadWriter.makePasteboardItem(
                    for: member,
                    securityScopedURLs: &draggedURLs
                ) else { continue }
                let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
                let image = dragPreviewImage ?? member.icon
                draggingItem.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
                draggingItems.append(draggingItem)
            }
            guard !draggingItems.isEmpty else { return }
            beginDraggingSession(with: draggingItems, event: event, source: self)
        }

        // MARK: 右键菜单

        private func presentContextMenu(with event: NSEvent) {
            let menu = NSMenu()
            let target = GroupMenuTarget(groupID: groupID)
            let isExpanded = ShelfStateViewModel.shared.expandedGroupIDs.contains(groupID)
            let view = NSMenuItem(title: isExpanded ? "收起查看" : "就地查看", action: #selector(GroupMenuTarget.expand(_:)), keyEquivalent: "")
            view.target = target
            let dissolve = NSMenuItem(title: "解散集合", action: #selector(GroupMenuTarget.dissolve(_:)), keyEquivalent: "")
            dissolve.target = target
            menu.addItem(view)
            menu.addItem(dissolve)
            menu.retainActionTarget(target)
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        // MARK: - NSDraggingSource

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            if Defaults[.copyOnDrag] {
                return [.copy]
            }
            switch context {
            case .outsideApplication:
                return [.copy, .move]
            case .withinApplication:
                return [.copy, .move, .generic]
            @unknown default:
                return [.copy]
            }
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            ShelfSelectionModel.shared.beginDrag()
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            ShelfSelectionModel.shared.endDrag()

            for url in draggedURLs {
                url.stopAccessingSecurityScopedResource()
                NSLog("🔐 Stopped security-scoped access after drag: \(url.path)")
            }
            draggedURLs.removeAll()

            // Auto-remove group items from shelf if enabled and drag succeeded
            if Defaults[.autoRemoveShelfItems] && !operation.isEmpty {
                for member in members {
                    ShelfStateViewModel.shared.remove(member)
                }
            }
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            false
        }
    }

    private final class GroupMenuTarget: NSObject {
        let groupID: UUID

        init(groupID: UUID) {
            self.groupID = groupID
        }

        @MainActor @objc func expand(_ sender: NSMenuItem) {
            ShelfStateViewModel.shared.toggleGroupExpanded(groupID)
        }

        @MainActor @objc func dissolve(_ sender: NSMenuItem) {
            ShelfStateViewModel.shared.dissolveGroup(groupID)
        }
    }
}
