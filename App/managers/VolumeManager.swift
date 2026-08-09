import AppKit
import Combine
import CoreAudio
import Foundation

/// 系统音量管理器，基于 CoreAudio 读写/监听系统输出设备音量。
/// 沙盒内可用，无需额外权限。
@MainActor
final class VolumeManager: NSObject, ObservableObject {
    static let shared = VolumeManager()

    @Published private(set) var rawVolume: Float = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var lastChangeAt: Date = .distantPast

    let visibleDuration: TimeInterval = 1.2

    private var didInitialFetch = false
    private let step: Float32 = 1.0 / 16.0
    // 硬件不支持 mute 时的软件降级
    private var previousVolumeBeforeMute: Float32 = 0.2
    private var softwareMuted: Bool = false
    /// 缓存当前默认输出设备 ID，避免每次读写/静音判断都做 CoreAudio 属性查询。
    /// 在 handleDefaultDeviceChange（默认设备变化回调）中置 nil 失效。
    private var cachedDeviceID: AudioObjectID?

    private override init() {
        super.init()
        setupAudioListener()
        fetchCurrentVolume()
    }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

    // MARK: - Public Control API
    @MainActor func increase(stepDivisor: Float = 1.0) {
        let divisor = max(stepDivisor, 0.25)
        let delta = step / Float32(divisor)
        let current = readVolumeInternal() ?? rawVolume
        let target = max(0, min(1, current + delta))
        setAbsolute(target)
        NotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func decrease(stepDivisor: Float = 1.0) {
        let divisor = max(stepDivisor, 0.25)
        let delta = step / Float32(divisor)
        let current = readVolumeInternal() ?? rawVolume
        let target = max(0, min(1, current - delta))
        setAbsolute(target)
        NotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func toggleMuteAction() {
        let deviceID = systemOutputDeviceID()
        var willBeMuted = false
        var resultingVolume: Float32 = rawVolume

        if deviceID == kAudioObjectUnknown {
            willBeMuted = !softwareMuted
            resultingVolume = willBeMuted ? 0 : previousVolumeBeforeMute
        } else {
            let currentMuted = isMutedInternal()
            willBeMuted = !currentMuted
            resultingVolume = willBeMuted ? 0 : (readVolumeInternal() ?? rawVolume)
        }

        toggleMuteInternal()
        NotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(willBeMuted ? 0 : resultingVolume))
    }

    func refresh() { fetchCurrentVolume() }

    func adjustRelative(delta: Float32) {
        if isMutedInternal() { toggleMuteInternal() }
        guard let current = readVolumeInternal() else {
            fetchCurrentVolume()
            return
        }
        let target = max(0, min(1, current + delta))
        writeVolumeInternal(target)
        publish(volume: target, muted: isMutedInternal(), touchDate: true)
    }

    @MainActor func setAbsolute(_ value: Float32) {
        let clamped = max(0, min(1, value))
        let currentlyMuted = isMutedInternal()
        if currentlyMuted && clamped > 0 {
            toggleMuteInternal()
        }

        writeVolumeInternal(clamped)

        if clamped == 0 && !currentlyMuted {
            toggleMuteInternal()
        }

        publish(volume: clamped, muted: isMutedInternal(), touchDate: true)
    }

    // MARK: - CoreAudio Helpers
    private func systemOutputDeviceID() -> AudioObjectID {
        if let cached = cachedDeviceID, cached != kAudioObjectUnknown {
            return cached
        }
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultDeviceID
        )
        if status != noErr { return kAudioObjectUnknown }
        if defaultDeviceID != kAudioObjectUnknown {
            cachedDeviceID = defaultDeviceID
        }
        return defaultDeviceID
    }

    private func fetchCurrentVolume() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        var volumes: [Float32] = []
        let candidateElements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2, 3, 4]
        for element in candidateElements {
            if let v = readValidatedScalar(deviceID: deviceID, element: element) {
                volumes.append(v)
            }
        }
        if !volumes.isEmpty {
            let avg = max(0, min(1, volumes.reduce(0, +) / Float32(volumes.count)))
            // 类已 @MainActor，listener block 经 Task { @MainActor in } 调度至此，
            // 无需再 DispatchQueue.main.async 二次跳转（会让 @Published 变更延后一个 runloop）
            if rawVolume != avg && didInitialFetch {
                lastChangeAt = Date()
            }
            rawVolume = avg
            didInitialFetch = true
        }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            var sizeNeeded: UInt32 = 0
            if AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
                sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
            {
                var muted: UInt32 = 0
                var mSize = sizeNeeded
                if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &mSize, &muted) == noErr
                {
                    let newMuted = muted != 0
                    if isMuted != newMuted { lastChangeAt = Date() }
                    isMuted = newMuted
                }
            }
        }
    }

    /// 已注册的设备级 listener（deviceID + address + block），切换默认设备时用于精确移除。
    private var deviceListenerBlocks: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    /// 系统级 listener block（默认输出设备变化）。存储引用以便退出时精确移除。
    private var systemListenerBlock: AudioObjectPropertyListenerBlock?

    private func setupAudioListener() {
        // 系统级：监听默认输出设备变化。切换设备时需重新注册新设备的 volume/mute listener，
        // 否则旧 deviceID 上的 listener 无法感知新设备变化。
        var defaultDevAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.handleDefaultDeviceChange() }
        }
        systemListenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDevAddr, nil, block
        )

        // 设备级：注册当前默认设备的 volume/mute listener
        registerDeviceListeners()
    }

    /// 默认输出设备变化时，失效 deviceID 缓存，移除旧设备 listener，注册新设备 listener，并拉取当前音量。
    private func handleDefaultDeviceChange() {
        cachedDeviceID = nil
        unregisterDeviceListeners()
        registerDeviceListeners()
        fetchCurrentVolume()
    }

    /// 在当前默认输出设备上注册 volume/mute 属性监听。
    private func registerDeviceListeners() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }

        var masterAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &masterAddr) {
            addDeviceListener(deviceID: deviceID, address: masterAddr)
        } else {
            for ch in [UInt32(1), UInt32(2)] {
                var chAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: ch
                )
                if AudioObjectHasProperty(deviceID, &chAddr) {
                    addDeviceListener(deviceID: deviceID, address: chAddr)
                }
            }
        }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            addDeviceListener(deviceID: deviceID, address: muteAddr)
        }
    }

    /// 注册单个属性监听并保存 block 引用，以便后续精确移除。
    private func addDeviceListener(deviceID: AudioObjectID, address: AudioObjectPropertyAddress) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.fetchCurrentVolume() }
        }
        var addr = address
        AudioObjectAddPropertyListenerBlock(deviceID, &addr, nil, block)
        deviceListenerBlocks.append((deviceID, address, block))
    }

    /// 移除所有已注册的设备级 listener。
    private func unregisterDeviceListeners() {
        for (deviceID, address, block) in deviceListenerBlocks {
            var addr = address
            AudioObjectRemovePropertyListenerBlock(deviceID, &addr, nil, block)
        }
        deviceListenerBlocks.removeAll()
    }

    private func readVolumeInternal() -> Float32? {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return nil }
        var collected: [Float32] = []
        for el in [kAudioObjectPropertyElementMain, 1, 2, 3, 4] {
            if let v = readValidatedScalar(deviceID: deviceID, element: el) { collected.append(v) }
        }
        guard !collected.isEmpty else { return nil }
        return collected.reduce(0, +) / Float32(collected.count)
    }

    private func writeVolumeInternal(_ value: Float32) {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return }
        let newVal = max(0, min(1, value))

        if writeValidatedScalar(
            deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: newVal)
        {
            return
        } else {
            for el in [UInt32](1...4) {
                if writeValidatedScalar(deviceID: deviceID, element: el, value: newVal) {
                    return
                }
            }
        }
    }

    private func isMutedInternal() -> Bool {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return softwareMuted }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &muteAddr) else { return softwareMuted }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        else { return softwareMuted }
        var muted: UInt32 = 0
        var size = sizeNeeded
        if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
        return softwareMuted
    }

    private func toggleMuteInternal() {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown {
            performSoftwareMuteToggle(currentVolume: rawVolume)
            return
        }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &muteAddr) {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
            return
        }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        else {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
            return
        }
        var muted: UInt32 = 0
        var size = sizeNeeded
        if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr {
            var newVal: UInt32 = muted == 0 ? 1 : 0
            AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, size, &newVal)
            let vol = readVolumeInternal() ?? rawVolume
            publish(volume: vol, muted: newVal != 0, touchDate: true)
        } else {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
        }
    }

    private func performSoftwareMuteToggle(currentVolume: Float32) {
        if softwareMuted {
            let restore = max(0, min(1, previousVolumeBeforeMute))
            writeVolumeInternal(restore)
            softwareMuted = false
            publish(volume: restore, muted: false, touchDate: true)
        } else {
            if currentVolume > 0.001 { previousVolumeBeforeMute = currentVolume }
            writeVolumeInternal(0)
            softwareMuted = true
            publish(volume: 0, muted: true, touchDate: true)
        }
    }

    private func readValidatedScalar(deviceID: AudioObjectID, element: UInt32) -> Float32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return nil }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return nil }
        var vol = Float32(0)
        var size = sizeNeeded
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        return status == noErr ? vol : nil
    }

    private func writeValidatedScalar(deviceID: AudioObjectID, element: UInt32, value: Float32) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return false }
        var val = value
        return AudioObjectSetPropertyData(deviceID, &addr, 0, nil, sizeNeeded, &val) == noErr
    }

    private func publish(volume: Float32, muted: Bool, touchDate: Bool) {
        // 类已 @MainActor，所有调用方均在 MainActor 上，无需 dispatch 到主线程
        if touchDate { lastChangeAt = Date() }
        rawVolume = volume
        isMuted = muted
    }
}
