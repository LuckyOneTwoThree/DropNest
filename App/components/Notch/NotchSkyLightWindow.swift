//
//  NotchSkyLightWindow.swift
//  DropNest
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    /// dlopen 结果缓存为静态句柄：避免每次 undelegateWindow 都重复打开动态库，
    /// 也避免 handle 为 nil 时 dlsym(nil, …) 误搜全局符号表。
    /// 进程生命周期内只加载一次，不 dlclose（私有框架本就被系统映射）。
    private static let skyLightHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
    }()

    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

        guard let handle = Self.skyLightHandle,
              let symbol = dlsym(handle, "SLSRemoveWindowsFromSpaces") else {
            return
        }
        let SLSRemoveWindowsFromSpaces = unsafeBitCast(symbol, to: F_SLSRemoveWindowsFromSpaces.self)

        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class NotchSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false

        // Only become key when a control actually needs keyboard input
        // (e.g. the clipboard search field); never steal focus otherwise.
        becomesKeyOnlyIfNeeded = true

        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
