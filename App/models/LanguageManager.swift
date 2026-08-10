//
//  LanguageManager.swift
//  DropNest
//
//  Created by Antigravity on 2026. 08. 10..
//

import SwiftUI
import Defaults

enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
    case system = "system"
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .system:
            return String(localized: "System Default", locale: LanguageManager.shared.currentLocale)
        case .english:
            return "English"
        case .chinese:
            return "简体中文"
        }
    }

    var locale: Locale? {
        switch self {
        case .system:
            return nil
        case .english:
            return Locale(identifier: "en")
        case .chinese:
            return Locale(identifier: "zh-Hans")
        }
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    /// 标记 init 是否完成。didSet 仅在外部修改时生效，避免 init 赋值触发重启。
    private var isInitialized = false

    @Published var currentLanguage: AppLanguage {
        didSet {
            // init 赋值时 isInitialized=false，跳过副作用
            guard isInitialized else { return }
            // 仅在语言真正发生变化时执行
            guard oldValue != currentLanguage else { return }
            Defaults[.appLanguage] = currentLanguage
            applyLanguage(currentLanguage)
            // AppleLanguages 写入 UserDefaults 后，Bundle.main.preferredLocalizations
            // 不会立即更新；LocalizedStringKey 查找仍会命中旧语言表。
            // 强制重启以确保所有视图（含 LocalizedStringKey）同步切换到新语言。
            ApplicationRelauncher.restart()
        }
    }

    var currentLocale: Locale {
        if let explicitLocale = currentLanguage.locale {
            return explicitLocale
        }
        // Resolve system language to match String Catalog identifiers ("zh-Hans" or "en")
        for lang in Locale.preferredLanguages {
            let lower = lang.lowercased()
            if lower.hasPrefix("zh") {
                return Locale(identifier: "zh-Hans")
            } else if lower.hasPrefix("en") {
                return Locale(identifier: "en")
            }
        }
        return Locale(identifier: "zh-Hans")
    }

    private init() {
        let saved = Defaults[.appLanguage]
        self.currentLanguage = saved
        applyLanguage(saved)
        isInitialized = true
    }

    func applyLanguage(_ lang: AppLanguage) {
        switch lang {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .chinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        objectWillChange.send()
    }
}
