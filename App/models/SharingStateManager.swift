//
//  SharingStateManager.swift
//  DropNest
//
//  Created by Alexander on 2025-10-10.
//

import AppKit
import Combine
import Foundation

extension Notification.Name {
	static let sharingDidFinish = Notification.Name("com.dropnest.sharingDidFinish")
}

@MainActor
final class SharingStateManager: ObservableObject {
	static let shared = SharingStateManager()

	private var activeSessions: Int = 0 {
		didSet {
			let newValue = activeSessions > 0
			if newValue != preventNotchClose {
				preventNotchClose = newValue
				if !newValue {
					NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
				}
			}
		}
	}

	@Published var preventNotchClose: Bool = false

	private var activeDelegates: [UUID: SharingLifecycleDelegate] = [:]

	private init() {}
	
	func requestCloseIfReady() {
		if !preventNotchClose {
			NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
		}
	}

	func beginInteraction() {
		activeSessions += 1
	}

	func endInteraction() {
		if activeSessions > 0 { activeSessions -= 1 }
	}

	func makeDelegate(onEnd: (() -> Void)? = nil) -> SharingLifecycleDelegate {
		let id = UUID()
		let delegate = SharingLifecycleDelegate(id: id, onEnd: { [weak self] in
			onEnd?()
			self?.unregisterDelegate(id: id)
		}, onBegin: { [weak self] in
			self?.beginInteraction()
		}, onFinish: { [weak self] in
			self?.endInteraction()
		})
		activeDelegates[id] = delegate
		return delegate
	}

	private func unregisterDelegate(id: UUID) {
		activeDelegates.removeValue(forKey: id)
	}
}

final class SharingLifecycleDelegate: NSObject, NSSharingServiceDelegate, NSSharingServicePickerDelegate {
	let id: UUID
	private let onEnd: () -> Void
	private let onBegin: () -> Void
	private let onFinish: () -> Void

	private var pickerActive = false
	private var serviceInProgress = false
	private var finished = false
	private var timeoutTask: Task<Void, Never>?
	private var pickerTimeoutTask: Task<Void, Never>?

	init(id: UUID, onEnd: @escaping () -> Void, onBegin: @escaping () -> Void, onFinish: @escaping () -> Void) {
		self.id = id
		self.onEnd = onEnd
		self.onBegin = onBegin
		self.onFinish = onFinish
	}

	deinit {
		timeoutTask?.cancel()
		pickerTimeoutTask?.cancel()
	}

	func markPickerBegan() {
		guard !pickerActive else { return }
		pickerActive = true
		onBegin()
		startPickerTimeoutFallback()
	}

	/// Picker 兜底：若 picker 弹出后未回调 didChoose（如点击外部 dismiss），
	/// 会话与 delegate 会永久泄漏、preventNotchClose 卡死。60 秒无响应则强制收尾。
	private func startPickerTimeoutFallback() {
		pickerTimeoutTask?.cancel()
		pickerTimeoutTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(60))
			guard let self = self, !Task.isCancelled else { return }
			if !self.finished && !self.serviceInProgress {
				print("⚠️ Sharing picker did not call back within 60s, force-finishing session")
				self.finishIfNeeded()
			}
		}
	}

	func markServiceBegan() {
		guard !serviceInProgress else { return }
		serviceInProgress = true
		onBegin()
		startTimeoutFallback()
	}
	
	private func startTimeoutFallback() {
		timeoutTask?.cancel()
		timeoutTask = Task { @MainActor [weak self] in
			try? await Task.sleep(for: .seconds(2))
			guard let self = self, !Task.isCancelled else { return }
			if !self.finished {
				self.finishIfNeeded()
			}
		}
	}

	private func finishIfNeeded() {
		guard !finished else { return }
		finished = true
		timeoutTask?.cancel()
		pickerTimeoutTask?.cancel()
		onFinish()
		onEnd()
	}

	// MARK: - NSSharingServicePickerDelegate

	func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
		// 用户已作出选择（含取消），picker 兜底使命结束
		pickerTimeoutTask?.cancel()
		if service == nil {
			if pickerActive && !serviceInProgress {
				finishIfNeeded()
			}
			return
		}

		service?.delegate = self
		serviceInProgress = true
		startTimeoutFallback()
	}

	// MARK: - NSSharingServiceDelegate

	func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
		if !pickerActive && !serviceInProgress {
			onBegin()
		}
		serviceInProgress = true
	}

	func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
		finishIfNeeded()
	}

	func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
		finishIfNeeded()
	}
}

