//
//  ClipboardQuickPanel.swift
//  DropNest
//
//  Created on 2026-08-07.
//  Keyboard-driven quick panel shown at the mouse cursor (P2).
//

import AppKit
import SwiftUI

// MARK: - Panel state

@MainActor
final class ClipboardQuickPanelState: ObservableObject {
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0

    func items(from store: ClipboardHistoryStore) -> [ClipboardItem] {
        ClipboardHistoryViewModel.shared.displayedItems(from: store.items, query: query)
    }

    func reset() {
        query = ""
        selectedIndex = 0
    }
}

// MARK: - Panel

final class ClipboardQuickPanel: NSPanel {
    private let state = ClipboardQuickPanelState()
    // nonisolated(unsafe)：NSPanel 子类隐式 @MainActor，monitor/observer token 仅在
    // MainActor 的 startKeyMonitor/init 中赋值、nonisolated deinit 中移除。
    // 标 nonisolated(unsafe) 允许 deinit 安全访问
    // （参照 DragDetector.swift 的 mouseDownMonitor 范式）。
    private nonisolated(unsafe) var keyMonitor: Any?
    private nonisolated(unsafe) var resignObserver: Any?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentView = NSHostingView(rootView: ClipboardQuickPanelRootView(state: state) { [weak self] item in
            self?.confirm(item)
        })

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    // nonactivating panel that still accepts keyboard input
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showAtMouse() {
        state.reset()
        let mouse = NSEvent.mouseLocation
        let frame = self.frame
        var origin = NSPoint(x: mouse.x - frame.width / 2, y: mouse.y - frame.height - 12)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            origin.x = min(max(origin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
            origin.y = max(origin.y, screen.visibleFrame.minY)
        }
        setFrameOrigin(origin)
        orderFrontRegardless()
        makeKey()
        startKeyMonitor()
    }

    @MainActor func hide() {
        stopKeyMonitor()
        orderOut(nil)
    }

    // MARK: - Keyboard

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent monitor handler 是 @Sendable 闭包（nonisolated），但回调在主线程 RunLoop 派发。
            // MainActor.assumeIsolated 向编译器声明隔离，零运行时开销。
            MainActor.assumeIsolated {
                guard let self, self.isKeyWindow else { return event }
                return self.handleKey(event) ? nil : event
            }
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    @MainActor private func handleKey(_ event: NSEvent) -> Bool {
        let items = state.items(from: ClipboardHistoryStore.shared)
        switch event.keyCode {
        case 53: // esc
            hide()
            return true
        case 125: // down
            state.selectedIndex = min(state.selectedIndex + 1, max(items.count - 1, 0))
            return true
        case 126: // up
            state.selectedIndex = max(state.selectedIndex - 1, 0)
            return true
        case 36, 76: // enter / keypad enter
            if items.indices.contains(state.selectedIndex) {
                confirm(items[state.selectedIndex])
            }
            return true
        case 51: // delete
            if !state.query.isEmpty { state.query.removeLast() }
            state.selectedIndex = 0
            return true
        default:
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let chars = event.characters, !chars.isEmpty else { return false }
            state.query.append(chars)
            state.selectedIndex = 0
            return true
        }
    }

    @MainActor private func confirm(_ item: ClipboardItem) {
        ClipboardHistoryStore.shared.copyBackToPasteboard(item)
        hide()
        // Let the panel disappear before injecting ⌘V into the user's app.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            ClipboardQuickPanelController.shared.performAutoPaste()
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}

// MARK: - SwiftUI content

private struct ClipboardQuickPanelRootView: View {
    @ObservedObject var state: ClipboardQuickPanelState
    @StateObject private var store = ClipboardHistoryStore.shared
    let onConfirm: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 8) {
            queryBar
            itemList
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
    }

    private var queryBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(state.query.isEmpty ? "输入以过滤 · ↑↓ 选择 · ⏎ 复制" : state.query)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(state.query.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var itemList: some View {
        let items = state.items(from: store)
        if items.isEmpty {
            Text("没有匹配的剪贴板记录")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemView(item: item) {
                                onConfirm(item)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(index == state.selectedIndex ? Color.accentColor.opacity(0.35) : Color.clear)
                            )
                            .id(index)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: state.selectedIndex) { _, newValue in
                    withAnimation(.smooth(duration: 0.1)) {
                        proxy.scrollTo(newValue)
                    }
                }
            }
        }
    }
}
