//
//  ShakeGestureDetector.swift
//  DropNest
//
//  摇晃手势检测（FR-F1）：拖拽活跃期内由 DragDetector.onDragMove 喂入全局坐标，
//  在最近时间窗内统计 X 方向反转次数与振幅，达到阈值即触发 onShake，随后进入冷却。
//  纯逻辑组件，无 UI 依赖；阈值走 Defaults，设置页可调（FR-F5）。
//

import AppKit
import Defaults

@MainActor
final class ShakeGestureDetector {
    static let shared = ShakeGestureDetector()

    /// 触发回调，参数为触发时刻的全局坐标
    var onShake: (CGPoint) -> Void = { _ in }

    // MARK: - 判定参数

    /// 采样时间窗（秒）
    private let window: TimeInterval = 0.8
    /// 触发所需 X 方向反转次数
    private let requiredReversals = 3
    /// 小于该值的单步位移视为手抖噪声，不参与方向统计
    private let noiseEpsilon: CGFloat = 1
    /// 触发后的冷却时长（秒）
    private let cooldown: TimeInterval = 1

    private var samples: [(point: CGPoint, time: TimeInterval)] = []
    private var cooldownUntil: TimeInterval = 0

    init() {}

    /// 拖拽活跃期内喂入全局坐标采样
    /// - Parameters:
    ///   - point: 全局屏幕坐标
    ///   - time: 采样时刻（默认取系统启动时间戳；测试可注入确定值）
    func feed(_ point: CGPoint, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        // 功能开关全链路生效：关闭时不采样、不判定
        guard Defaults[.floatingNestEnabled] else { return }

        samples.append((point, time))
        // 仅保留最近 window 内的采样（拖拽事件约 60~120Hz，数组规模 <100，开销可忽略）
        let cutoff = time - window
        samples.removeAll { $0.time < cutoff }

        guard time >= cooldownUntil else { return }
        guard samples.count > requiredReversals else { return }

        // X 方向符号反转统计 + 峰峰值振幅
        var reversals = 0
        var lastSign = 0
        var minX = samples[0].point.x
        var maxX = minX
        for i in 1..<samples.count {
            let x = samples[i].point.x
            minX = min(minX, x)
            maxX = max(maxX, x)
            let dx = x - samples[i - 1].point.x
            guard abs(dx) >= noiseEpsilon else { continue }
            let sign = dx > 0 ? 1 : -1
            if lastSign != 0 && sign != lastSign { reversals += 1 }
            lastSign = sign
        }

        // 灵敏度映射：sensitivity 越高所需振幅越低（0.5 时即为基准振幅）
        let minAmplitude = CGFloat(Defaults[.shakeMinAmplitude] * (1.5 - Defaults[.shakeSensitivity]))
        guard reversals >= requiredReversals, maxX - minX >= minAmplitude else { return }

        cooldownUntil = time + cooldown
        samples.removeAll()
        onShake(point)
    }

    /// 拖拽结束 / 离开刘海区域时清空采样
    func reset() {
        samples.removeAll()
    }
}
