//
//  NotchHeader.swift
//  DropNest
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//  Trimmed to minimal header (notch mask + settings button) on 2026-08-07.
//

import Defaults
import SwiftUI

struct NotchHeader: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject var coordinator = NotchViewCoordinator.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if vm.notchState == .open {
                    openTabBar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 4) {
                if vm.notchState == .open {
                    // 展开态 HUD（音量/亮度按键时显示）
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(
                            type: $coordinator.sneakPeek.type,
                            value: $coordinator.sneakPeek.value,
                            icon: $coordinator.sneakPeek.icon
                        )
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.settingsIconInNotch] {
                            Button(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                            }) {
                                Capsule()
                                    .fill(.black)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        Image(systemName: "gear")
                                            .foregroundColor(.white)
                                            .padding()
                                            .imageScale(.medium)
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        if Defaults[.showBatteryIndicator] {
                            BoringBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    @ViewBuilder
    private var openTabBar: some View {
        HStack(spacing: 6) {
            ForEach(vm.enabledTabs, id: \.self) { tab in
                tabButton(
                    title: tab == .shelf ? "文件架" : "剪贴板",
                    icon: tab == .shelf ? "books.vertical" : "clipboard",
                    tab: tab
                )
            }
        }
        .padding(.leading, 12)
    }

    private func tabButton(title: String, icon: String, tab: NotchOpenTab) -> some View {
        let selected = vm.openTab == tab
        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                vm.openTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(selected ? Color.white.opacity(0.16) : Color.clear)
            .clipShape(Capsule())
            .foregroundStyle(selected ? .white : .gray)
        }
        .buttonStyle(.plain)
    }

    /// 判断是否为 HUD 类型（音量/亮度/背光）
    private func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight:
            return true
        default:
            return false
        }
    }
}

#Preview {
    NotchHeader().environmentObject(NotchViewModel())
}
