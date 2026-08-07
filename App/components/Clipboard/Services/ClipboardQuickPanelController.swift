//
//  ClipboardQuickPanelController.swift
//  DropNest
//
//  Created on 2026-08-07.
//  Global hotkey (Carbon RegisterEventHotKey — no Accessibility needed) +
//  quick panel lifecycle + optional auto-paste via CGEvent (Accessibility-gated).
//

import AppKit
import Carbon.HIToolbox
import Defaults
import Foundation

@MainActor
final class ClipboardQuickPanelController {
    static let shared = ClipboardQuickPanelController()

    private var panel: ClipboardQuickPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyObservation: Defaults.Observation?
    private var historyObservation: Defaults.Observation?

    /// Default hotkey: ⌃⌥V
    private let hotKeyCode: UInt32 = UInt32(kVK_ANSI_V)
    private let hotKeyModifiers: UInt32 = UInt32(controlKey | optionKey)

    private init() {
        hotkeyObservation = Defaults.observe(.clipboardHotkeyEnabled) { [weak self] change in
            Task { @MainActor in
                if change.newValue { self?.registerHotkey() } else { self?.unregisterHotkey() }
            }
        }
        // Disabling clipboard history also disables the quick panel entirely.
        historyObservation = Defaults.observe(.clipboardHistoryEnabled) { [weak self] change in
            Task { @MainActor in
                if change.newValue {
                    if Defaults[.clipboardHotkeyEnabled] { self?.registerHotkey() }
                } else {
                    self?.unregisterHotkey()
                    self?.hidePanel()
                }
            }
        }
    }

    func startIfEnabled() {
        if Defaults[.clipboardHotkeyEnabled] { registerHotkey() }
    }

    // MARK: - Hotkey (Carbon)

    private func registerHotkey() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userInfo in
            guard let userInfo else { return noErr }
            let controller = Unmanaged<ClipboardQuickPanelController>.fromOpaque(userInfo).takeUnretainedValue()
            Task { @MainActor in controller.togglePanel() }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x444E4342), id: 1) // 'DNCB'
        RegisterEventHotKey(hotKeyCode, hotKeyModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotkey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
    }

    // MARK: - Panel

    func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        if panel == nil {
            panel = ClipboardQuickPanel()
        }
        panel?.showAtMouse()
    }

    func hidePanel() {
        panel?.hide()
    }

    // MARK: - Auto-paste

    /// Synthesizes ⌘V into the currently active app. Requires Accessibility
    /// trust; callers must degrade gracefully when untrusted.
    func performAutoPaste() {
        guard Defaults[.clipboardAutoPaste] else { return }
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Called when the user enables auto-paste without having granted
    /// Accessibility — guides to System Settings instead of failing silently.
    func promptForAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }
}
