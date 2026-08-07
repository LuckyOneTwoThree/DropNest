//
//  ContentView.swift
//  DropNestApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//  Trimmed to Shelf + media status bar only (2026-08-07).
//

import Combine
import Defaults
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        // 电池横向通知优先级最高，扩展到展开态宽度
        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )

                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchSize)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !SharingStateManager.shared.preventNotchClose {
                                        withAnimation(self.animationSpring) {
                                            self.vm.close()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("设置") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                // Any drag entering the notch area is treated as "shelf deposit":
                // switch to the shelf tab so the dropped content is visible.
                if Defaults[.boringShelf] {
                    withAnimation(.smooth(duration: 0.2)) {
                        vm.openTab = .shelf
                    }
                }
                if vm.notchState == .closed {
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    withAnimation(animationSpring) {
                        vm.close()
                    }
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                // 电池横向通知（电源/充电/低功耗变化时短闪）
                if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                    && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                {
                    HStack(spacing: 0) {
                        HStack {
                            Text(batteryModel.statusText)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                        }

                        Rectangle()
                            .fill(.black)
                            .frame(width: vm.closedNotchSize.width + 10)

                        HStack {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                isForNotification: true
                            )
                        }
                        .frame(width: 76, alignment: .trailing)
                    }
                    .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                } else if coordinator.sneakPeek.show && Defaults[.inlineHUD]
                    && coordinator.sneakPeek.type != .music
                    && coordinator.sneakPeek.type != .battery
                    && vm.notchState == .closed
                {
                    // 折叠态内联 HUD（音量/亮度/背光）
                    InlineHUD(
                        type: $coordinator.sneakPeek.type,
                        value: $coordinator.sneakPeek.value,
                        icon: $coordinator.sneakPeek.icon,
                        hoverAnimation: $isHovering,
                        gestureProgress: $gestureProgress
                    )
                    .transition(.opacity)
                } else if vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
                    && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
                {
                    MusicLiveActivity()
                        .frame(alignment: .center)
                } else if vm.notchState == .open {
                    NotchHeader()
                        .frame(height: max(24, vm.effectiveClosedNotchHeight))
                        .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                } else {
                    Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                }

                // 折叠态非内联 HUD（默认样式，在刘海下方显示进度条）
                if coordinator.sneakPeek.show
                    && coordinator.sneakPeek.type != .music
                    && coordinator.sneakPeek.type != .battery
                    && !Defaults[.inlineHUD]
                    && vm.notchState == .closed
                {
                    SystemEventIndicatorModifier(
                        eventType: $coordinator.sneakPeek.type,
                        value: $coordinator.sneakPeek.value,
                        icon: $coordinator.sneakPeek.icon,
                        sendEventBack: { newVal in
                            switch coordinator.sneakPeek.type {
                            case .volume:
                                VolumeManager.shared.setAbsolute(Float32(newVal))
                            case .brightness:
                                BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                            case .backlight:
                                KeyboardBacklightManager.shared.setAbsolute(value: Float32(newVal))
                            default:
                                break
                            }
                        }
                    )
                    .padding(.bottom, 10)
                }
            }
            .zIndex(2)
            if vm.notchState == .open {
                VStack(spacing: 8) {
                    Group {
                        switch vm.openTab {
                        case .shelf:
                            ShelfView()
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        case .clipboard:
                            ClipboardHistoryView()
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.generalDropTargeting) { providers in
            guard Defaults[.boringShelf] else { return false }
            ShelfStateViewModel.shared.load(providers)
            return true
        }
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Rectangle()
                .fill(
                    Defaults[.coloredSpectrogram]
                        ? Color(nsColor: musicManager.avgColor).gradient
                        : Color.gray.gradient
                )
                .frame(width: 50, alignment: .center)
                .mask {
                    AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                        .frame(width: 16, height: 12)
                }
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            applyDefaultTab()
            vm.open()
        }
    }

    /// Picks the default tab for this open based on the most recent activity:
    /// last copy → clipboard (when it has content), last shelf deposit → shelf
    /// (when it has content), otherwise the first enabled tab.
    private func applyDefaultTab() {
        let shelfEnabled = Defaults[.boringShelf]
        let clipboardEnabled = Defaults[.clipboardHistoryEnabled]
        let hasClipboardContent = !ClipboardHistoryStore.shared.items.isEmpty
        let hasShelfContent = !ShelfStateViewModel.shared.items.isEmpty

        switch NotchTabPreference.lastActivity {
        case .copy where clipboardEnabled && hasClipboardContent:
            vm.openTab = .clipboard
        case .shelfDeposit where shelfEnabled && hasShelfContent:
            vm.openTab = .shelf
        default:
            vm.openTab = shelfEnabled ? .shelf : .clipboard
        }
        vm.ensureValidTab()
    }

    /// True while the notch is open on the clipboard tab — scrolling the
    /// history must not be hijacked by the notch's down-swipe gesture.
    private var isClipboardTabOpen: Bool {
        vm.notchState == .open && vm.openTab == .clipboard
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }

            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering else { return }

                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false

                        if self.vm.notchState == .open
                            && !SharingStateManager.shared.preventNotchClose
                            && !self.vm.isBatteryPopoverActive
                        {
                            self.vm.close()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        // Never hijack scrolling inside the clipboard history tab.
        guard vm.notchState == .closed, !isClipboardTabOpen else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        // Never hijack scrolling inside the clipboard history tab.
        guard vm.notchState == .open, !isClipboardTabOpen else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
                if !SharingStateManager.shared.preventNotchClose {
                    gestureProgress = .zero
                    vm.close()
                }
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

#Preview {
    let vm = NotchViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
