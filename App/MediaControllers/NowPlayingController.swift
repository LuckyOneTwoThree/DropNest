//
//  NowPlayingController.swift
//  DropNest
//
//  Created by Alexander on 2025-03-29.
//  Trimmed to stream listening only (no media commands) on 2026-08-07.
//

import AppKit
import Combine
import Foundation

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        // No-op: state arrives via the media stream
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    /// 媒体流每秒可产生数条 JSON 行，逐条新建 formatter 属于高频小对象分配（且 ISO8601DateFormatter 初始化并不便宜）。
    /// 二者均为只读用法，复用同一实例即可。
    private static let iso8601Formatter = ISO8601DateFormatter()

    // MARK: - Initialization
    init?() {
        Task { await setupNowPlayingObserver() }
    }

    deinit {
        streamTask?.cancel()

        if let process = self.process, process.isRunning {
            process.terminate()
        }

        self.process = nil
        self.pipeHandler = nil
    }

    func isActive() -> Bool {
        return true
    }

    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
        else {
            // Release 版 assertionFailure 会被编译掉，媒体功能静默失效且无任何线索；改为始终可见的日志
            print("❌ [NowPlaying] 找不到 mediaremote-adapter.pl 或 MediaRemoteAdapter.framework，媒体信息将不可用")
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, "stream"]

        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()

        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            print("❌ [NowPlaying] 启动 mediaremote-adapter.pl 失败：\(error.localizedDescription)")
            self.process = nil
            self.pipeHandler = nil
            assertionFailure("Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    // MARK: - Async Stream Processing
    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }

        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)

        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? self.playbackState.duration : 0)

        if let elapsedTime = payload.elapsedTime {
            newPlaybackState.currentTime = elapsedTime
        } else if diff {
            if payload.playing == false {
                let timeSinceLastUpdate = Date().timeIntervalSince(self.playbackState.lastUpdated)
                newPlaybackState.currentTime = self.playbackState.currentTime + (self.playbackState.playbackRate * timeSinceLastUpdate)
            } else {
                newPlaybackState.currentTime = self.playbackState.currentTime
            }
        } else {
            newPlaybackState.currentTime = 0
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if !diff {
            newPlaybackState.artwork = nil
        }

        if let dateString = payload.timestamp,
           let date = Self.iso8601Formatter.date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if !diff {
            newPlaybackState.lastUpdated = Date()
        } else {
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )

        await MainActor.run { self.playbackState = newPlaybackState }
    }
}

struct NowPlayingUpdate: Codable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    /// 复用解码器：媒体流按行高频解码，逐行新建 JSONDecoder 是纯粹的分配浪费
    private let decoder = JSONDecoder()

    /// 挂起的读取 continuation。readabilityHandler 在系统队列触发（非 actor 隔离），
    /// 用锁保证恰好 resume 一次；close()/任务取消时兜底 resume，避免 Task 永久泄漏。
    private final class PendingReadBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, any Error>?

        func install(_ c: CheckedContinuation<Data, any Error>) {
            lock.lock()
            continuation = c
            lock.unlock()
        }

        func resume(returning data: Data) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: data)
        }

        func resume(throwing error: any Error) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(throwing: error)
        }
    }

    private let pendingRead = PendingReadBox()

    init() {
        self.pipe = Pipe()
        self.fileHandle = pipe.fileHandleForReading
    }

    func getPipe() -> Pipe {
        return pipe
    }

    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            try await self.processLines(as: type) { decodedObject in
                await onLine(decodedObject)
            }
        } catch {
            print("Error processing JSON stream: \(error)")
        }
    }

    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }

            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)

                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])

                    if !line.isEmpty {
                        await processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }

    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) async -> Void) async {
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let decodedObject = try decoder.decode(T.self, from: data)
            await onLine(decodedObject)
        } catch {
            // Ignore lines that can't be decoded
        }
    }

    private func readData() async throws -> Data {
        let box = pendingRead
        let handle = fileHandle
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                box.install(continuation)
                handle.readabilityHandler = { h in
                    let data = h.availableData
                    h.readabilityHandler = nil
                    box.resume(returning: data)
                }
            }
        } onCancel: {
            // 任务取消时兜底 resume，避免 continuation 永久悬挂导致 Task 泄漏
            handle.readabilityHandler = nil
            box.resume(throwing: CancellationError())
        }
    }

    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            // 若 readData 正挂起，以空数据放行（processLines 会按 EOF 正常退出循环）
            pendingRead.resume(returning: Data())
            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            print("Error closing pipe handler: \(error)")
        }
    }
}
