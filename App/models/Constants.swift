//
//  Constants.swift
//  DropNest
//
//  Created by Richard Kunkli on 2024. 10. 17..
//  Trimmed: shelf + media bar settings only (2026-08-07).
//

import SwiftUI
import Defaults

let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"

    var localizedTitle: String {
        switch self {
        case .matchMenuBar:
            return String(localized: "Match menu bar height", locale: LanguageManager.shared.currentLocale)
        case .matchRealNotchSize:
            return String(localized: "Match real notch height", locale: LanguageManager.shared.currentLocale)
        case .custom:
            return String(localized: "Custom height", locale: LanguageManager.shared.currentLocale)
        }
    }
}

/// 按住 Option 键时按媒体键的行为
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "openSettings"
    case showHUD = "showHUD"
    case none = "none"

    var id: String { self.rawValue }

    var localizedTitle: String {
        switch self {
        case .openSettings:
            return String(localized: "Open System Settings", locale: LanguageManager.shared.currentLocale)
        case .showHUD:
            return String(localized: "Show HUD", locale: LanguageManager.shared.currentLocale)
        case .none:
            return String(localized: "No Action", locale: LanguageManager.shared.currentLocale)
        }
    }

    // 旧持久化值是中文 rawValue（"打开系统设置"/"显示 HUD"/"无操作"），
    // 升级到英文标识符后需在解码时迁移，避免读取旧 UserDefaults 失败回退到默认值。
    static let legacyRawValueMap: [String: OptionKeyAction] = [
        "打开系统设置": .openSettings,
        "显示 HUD": .showHUD,
        "无操作": .none
    ]

    /// App 启动早期调用：将旧版中文 rawValue 迁移到新的英文标识符。
    static func migrateLegacyRawValueIfNeeded() {
        let keyName = "optionKeyAction"
        guard let raw = UserDefaults.standard.object(forKey: keyName) as? String else {
            return
        }
        // 当前 rawValue 集合已是英文标识符；若 UserDefaults 里存的还是中文，则迁移。
        guard OptionKeyAction(rawValue: raw) == nil,
              let migrated = legacyRawValueMap[raw] else {
            return
        }
        Defaults[.optionKeyAction] = migrated
    }
}

extension Defaults.Keys {
    // MARK: General
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "DropNest 🪺")

    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)

    // MARK: Appearance
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)

    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let waitInterval = Key<Double>("waitInterval", default: 3)

    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: true)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    /// FR-N11：批量拖入自动成组
    static let nestAutoGroupOnBatchDrop = Key<Bool>("nestAutoGroupOnBatchDrop", default: false)

    // MARK: Floating Nest（悬浮暂存巢群）
    /// FR-F5：悬浮暂存巢总开关（关闭时检测器与巢群全链路停用）
    static let floatingNestEnabled = Key<Bool>("floatingNestEnabled", default: true)
    /// 摇晃灵敏度 0~1，越高所需振幅越小
    static let shakeSensitivity = Key<Double>("shakeSensitivity", default: 0.5)
    /// 摇晃判定基准振幅（pt）
    static let shakeMinAmplitude = Key<Double>("shakeMinAmplitude", default: 8)
    /// v2：拖拽开始即自动显示空巢胚（false = 仅摇晃召唤）
    static let nestShowOnDragStart = Key<Bool>("nestShowOnDragStart", default: true)
    /// v2：网格列数上限（2~4，默认 3），超出纵向滚动
    static let nestMaxGridColumns = Key<Int>("nestMaxGridColumns", default: 3)
    /// v2：正式巢位置记忆（groupID 字符串 → "x,y" 编码）
    static let nestPositions = Key<[String: String]>("nestPositions", default: [:])
    /// 旧键（已废弃，由 nestShowOnDragStart 替代），保留以兼容旧设置
    static let floatingNestAutoShowOnDrag = Key<Bool>("floatingNestAutoShowOnDrag", default: false)

    // MARK: Clipboard
    static let clipboardHistoryEnabled = Key<Bool>("clipboardHistoryEnabled", default: true)
    static let clipboardMaxItems = Key<Int>("clipboardMaxItems", default: 5)
    static let clipboardRetentionDays = Key<Int>("clipboardRetentionDays", default: 0) // 0 = 永不过期
    static let clipboardKeepImages = Key<Bool>("clipboardKeepImages", default: true)
    static let clipboardKeepFiles = Key<Bool>("clipboardKeepFiles", default: true)
    static let clipboardMaxItemSizeMB = Key<Int>("clipboardMaxItemSizeMB", default: 10)
    static let clipboardIgnoredApps = Key<[String]>("clipboardIgnoredApps", default: [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess"
    ])
    static let clipboardHotkeyEnabled = Key<Bool>("clipboardHotkeyEnabled", default: true)
    static let clipboardAutoPaste = Key<Bool>("clipboardAutoPaste", default: false) // 需辅助功能权限

    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)

    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    /// 各能力独立开关（在 hudReplacement 主开关开启的前提下，单独控制各类按键的拦截与 HUD 显示）
    static let volumeHUDEnabled = Key<Bool>("volumeHUDEnabled", default: true)
    static let brightnessHUDEnabled = Key<Bool>("brightnessHUDEnabled", default: true)
    static let keyboardBacklightHUDEnabled = Key<Bool>("keyboardBacklightHUDEnabled", default: true)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)

    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
