//
//  generic.swift
//  DropNest
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//  Trimmed (2026-08-07).
//

import Foundation
import Defaults

public enum Style {
    case notch
    case floating
}

public enum ContentType: Int, Codable, Hashable, Equatable {
    case normal
    case menu
    case settings
}

public enum NotchState {
    case closed
    case open
}

enum SettingsEnum {
    case general
    case about
    case mediaPlayback
    case shelf
}
