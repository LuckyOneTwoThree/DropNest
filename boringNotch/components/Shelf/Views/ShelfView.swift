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
                    Text("确认清空？")
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.semibold)
                } else {
                    Text("清空")
                        .font(.system(.caption, design: .rounded))
                }
            }
            .foregroundStyle(confirmClear ? .red : .red.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("清空文件架全部内容")
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

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)

                    Text("把文件拖到这里")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                VStack(spacing: 6) {
                    HStack {
                        Text("\(tvm.items.count) 项")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.gray)
                        Spacer()
                        clearButton
                    }
                    .padding(.horizontal, 4)

                    ScrollView(.horizontal) {
                        HStack(spacing: spacing) {
                            ForEach(tvm.items) { item in
                                ShelfItemView(item: item)
                                    .environmentObject(quickLookService)
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
