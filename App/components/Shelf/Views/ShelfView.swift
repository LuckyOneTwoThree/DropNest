//
//  ShelfItemView.swift
//  DropNest
//
//  Created by Alexander on 2025-09-24.
//  Trimmed: pure file grid, no share panel (2026-08-07).
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: NotchViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var confirmClear: Bool = false
    @State private var confirmResetTask: Task<Void, Never>?
    private let spacing: CGFloat = 8

    var body: some View {
        panel
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                handleDrop(providers: providers)
            }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        guard Defaults[.boringShelf] else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }

    /// Two-step clear: first tap arms ("确认清空？"), second tap executes.
    /// Avoids system alert sheets that may not present reliably on the
    /// non-activating notch panel.
    private var clearButton: some View {
        Button(role: .destructive) {
            if confirmClear {
                confirmResetTask?.cancel()
                confirmClear = false
                ShelfStateViewModel.shared.clearAll()
            } else {
                confirmClear = true
                confirmResetTask?.cancel()
                confirmResetTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    confirmClear = false
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: confirmClear ? "exclamationmark.triangle.fill" : "trash")
                    .font(.system(size: 11))
                if confirmClear {
                    Text("Confirm Clear?")
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.semibold)
                } else {
                    Text("Clear")
                        .font(.system(.caption, design: .rounded))
                }
            }
            .foregroundStyle(confirmClear ? .red : .red.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("Clear all shelf contents")
        .animation(.smooth(duration: 0.15), value: confirmClear)
    }

    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }

        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }

        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    /// 一键展开/收起全部桌面巢群。仅当存在集合组时显示。
    @ViewBuilder
    private var nestGroupButton: some View {
        // O(1) 字典判空，替代 O(n) 的 items.contains 遍历。
        // groupedItems 在 items didSet 时已一次性构建。
        let hasGroups = !tvm.groupedItems.isEmpty
        if hasGroups {
            Button {
                if FloatingNestManager.shared.hasVisiblePanels {
                    FloatingNestManager.shared.dockAll()
                } else {
                    FloatingNestManager.shared.showAll()
                }
            } label: {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 11))
                    .foregroundStyle(FloatingNestManager.shared.hasVisiblePanels ? Color.accentColor : Color.gray)
            }
            .buttonStyle(.plain)
            .help(FloatingNestManager.shared.hasVisiblePanels ? "Collapse All Floating Nests" : "Expand All Floating Nests")
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                vm.dragDetectorTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
    }

    /// 渲染单元 + 集合序号命名（「集合 N」按出现顺序编号）
    private var namedEntries: [(entry: ShelfEntry, name: String)] {
        var ordinal = 0
        return tvm.entries.map { entry in
            if case .group = entry {
                ordinal += 1
                let groupPrefix = String(localized: "Group", locale: LanguageManager.shared.currentLocale)
                return (entry, "\(groupPrefix) \(ordinal)")
            }
            return (entry, "")
        }
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)

                    Text("Drag files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                VStack(spacing: 14) {
                    HStack {
                        Text("\(tvm.items.count) items")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.gray)
                        Spacer()
                        nestGroupButton
                        clearButton
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, -4) // 顶栏向虚线边框靠近

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: spacing) {
                            ForEach(namedEntries, id: \.entry.id) { named in
                                switch named.entry {
                                case .single(let item):
                                    ShelfItemView(item: item)
                                        .equatable()
                                        .environmentObject(quickLookService)
                                case .group(let groupID, let members):
                                    NestGroupCardView(groupID: groupID, members: members, name: named.name)
                                        .equatable()
                                        .environmentObject(quickLookService)
                                }
                            }
                        }
                    }
                    .padding(-spacing)
                    .scrollIndicators(.never)
                    .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                        handleDrop(providers: providers)
                    }
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
