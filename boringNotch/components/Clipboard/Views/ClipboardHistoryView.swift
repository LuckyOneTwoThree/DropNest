//
//  ClipboardHistoryView.swift
//  DropNest
//
//  Created on 2026-08-07.
//  Notch tab: browse / search clipboard history, click to copy back.
//

import SwiftUI

struct ClipboardHistoryView: View {
    @StateObject private var store = ClipboardHistoryStore.shared
    @StateObject private var cvm = ClipboardHistoryViewModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var confirmClear: Bool = false
    @State private var confirmResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 6) {
            if !store.items.isEmpty {
                searchBar
            }
            content
        }
        .quickLookPresenter(using: quickLookService)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("搜索剪贴板历史", text: $cvm.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .rounded))
                if !cvm.searchText.isEmpty {
                    Button {
                        cvm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Clear button lives OUTSIDE the search field capsule.
            clearButton
        }
        .padding(.horizontal, 12)
    }

    /// Two-step clear: first tap arms ("确认清空？"), second tap executes.
    /// Avoids system alert sheets that may not present reliably on the
    /// non-activating notch panel.
    private var clearButton: some View {
        Button(role: .destructive) {
            if confirmClear {
                confirmResetTask?.cancel()
                confirmClear = false
                store.clearAll()
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
                }
            }
            .foregroundStyle(confirmClear ? .red : .red.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("清空全部剪贴板历史")
        .animation(.smooth(duration: 0.15), value: confirmClear)
    }

    @ViewBuilder
    private var content: some View {
        let displayed = cvm.displayedItems(from: store.items)
        if store.items.isEmpty {
            emptyState(icon: "clipboard", text: "暂无剪贴板历史", hint: "复制的文本、图片和文件会出现在这里")
        } else if displayed.isEmpty {
            emptyState(icon: "magnifyingglass", text: "没有匹配的记录", hint: "换个关键词试试")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(displayed) { item in
                        ClipboardItemView(item: item) {
                            cvm.copyBack(item)
                        }
                        .contextMenu {
                            Button(item.isPinned ? "取消置顶" : "置顶") {
                                store.togglePin(item)
                            }
                            let qlURLs = cvm.quickLookURLs(for: item)
                            if !qlURLs.isEmpty {
                                Button("快速查看") {
                                    quickLookService.show(urls: qlURLs)
                                }
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                store.remove(item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.never)
        }
    }

    private func emptyState(icon: String, text: String, hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white, .gray)
                .imageScale(.large)
            Text(text)
                .foregroundStyle(.gray)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.medium)
            Text(hint)
                .foregroundStyle(.gray.opacity(0.7))
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
