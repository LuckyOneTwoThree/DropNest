//
//  NotchViewModel.swift
//  DropNest
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//  Trimmed to shelf + media bar only (2026-08-07).
//

import Combine
import Defaults
import SwiftUI

/// Tabs available in the open notch.
enum NotchOpenTab: String, CaseIterable {
    case shelf
    case clipboard
}

/// Tracks the most recent clipboard/shelf activity so the notch can pick a
/// sensible default tab on the next open:
/// copy → clipboard (if it has content), shelf deposit → shelf (if it has
/// content), otherwise fall back to the shelf tab.
@MainActor
enum NotchTabPreference {
    enum LastActivity {
        case none
        case copy
        case shelfDeposit
    }

    static var lastActivity: LastActivity = .none
}

class NotchViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = NotchViewCoordinator.shared

    let animationLibrary: NotchAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed
    /// Which tab is shown in the open notch: shelf or clipboard history.
    @Published var openTab: NotchOpenTab = .shelf

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []

    /// Tabs currently enabled by their settings toggles. Falls back to shelf
    /// if both features are disabled (unlikely, but keeps the bar non-empty).
    var enabledTabs: [NotchOpenTab] {
        var tabs: [NotchOpenTab] = []
        if Defaults[.boringShelf] { tabs.append(.shelf) }
        if Defaults[.clipboardHistoryEnabled] { tabs.append(.clipboard) }
        return tabs.isEmpty ? [.shelf] : tabs
    }

    /// Repairs openTab after a feature toggle disables the current tab.
    func ensureValidTab() {
        let shelfEnabled = Defaults[.boringShelf]
        let clipboardEnabled = Defaults[.clipboardHistoryEnabled]
        if !shelfEnabled && openTab == .shelf { openTab = .clipboard }
        if !clipboardEnabled && openTab == .clipboard { openTab = .shelf }
    }

    @Published var hideOnClosed: Bool = false

    @Published var edgeAutoOpenActive: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()

    /// Live clipboard history row count, kept in sync by ClipboardHistoryStore.
    /// Non-isolated storage so the view model can size the notch without
    /// crossing actor boundaries.
    static var clipboardRowCount: Int = 0

    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()

        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)

        // Switching tabs while open re-sizes the notch (clipboard is taller).
        $openTab
            .sink { [weak self] tab in
                guard let self, self.notchState == .open else { return }
                self.notchSize = tab == .clipboard
                    ? CGSize(width: clipboardOpenNotchSize.width, height: self.clipboardOpenHeight())
                    : openNotchSize
            }
            .store(in: &cancellables)

        // Feature toggles may disable the currently selected tab.
        for key in [Defaults.Keys.boringShelf, Defaults.Keys.clipboardHistoryEnabled] {
            featureObservations.append(Defaults.observe(key) { [weak self] _ in
                Task { @MainActor in
                    self?.ensureValidTab()
                }
            })
        }
    }

    private var featureObservations: [Defaults.Observation] = []

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {

            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2

            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }

        return false
    }

    func open() {
        // Clipboard tab is adaptive: at least the shelf height (190), up to
        // ~5 history rows (280). Fewer rows → shorter notch.
        self.notchSize = openTab == .clipboard
            ? CGSize(width: clipboardOpenNotchSize.width, height: clipboardOpenHeight())
            : openNotchSize
        self.notchState = .open

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    /// Adaptive height for the clipboard tab.
    private func clipboardOpenHeight() -> CGFloat {
        let rowHeight: CGFloat = 42
        let chromeHeight: CGFloat = 70 // header + search bar + spacing
        let target = chromeHeight + CGFloat(Self.clipboardRowCount) * rowHeight
        return min(clipboardOpenNotchSize.height, max(openNotchSize.height, target))
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.edgeAutoOpenActive = false
    }
}
