//
//  MediaControllerProtocol.swift
//  DropNest
//
//  Created by Alexander on 2025-03-29.
//  Trimmed to NowPlaying listener only (2026-08-07).
//

import Foundation
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }

    func isActive() -> Bool
    func updatePlaybackInfo() async
}
