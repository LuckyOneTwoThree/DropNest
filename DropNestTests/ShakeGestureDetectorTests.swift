//
//  ShakeGestureDetectorTests.swift
//  DropNestTests
//
//  摇晃检测纯逻辑测试：构造采样序列验证触发 / 不触发 / 冷却 / 开关停用。
//  通过注入确定性的采样时刻，避免依赖真实时钟。
//

import XCTest
import Defaults
@testable import DropNest

@MainActor
final class ShakeGestureDetectorTests: XCTestCase {

    /// 以固定阈值构造检测器（默认值：灵敏度 0.5 → 所需振幅 8pt）
    private func makeDetector(onShake: @escaping (CGPoint) -> Void) -> ShakeGestureDetector {
        Defaults[.floatingNestEnabled] = true
        Defaults[.shakeSensitivity] = 0.5
        Defaults[.shakeMinAmplitude] = 8
        let detector = ShakeGestureDetector()
        detector.onShake = onShake
        return detector
    }

    /// 从 startTime 起喂入一段左右往返序列（segments 个方向段，每段步长 amplitude、间隔 step）
    /// - Returns: 序列结束时刻
    @discardableResult
    private func feedShake(
        _ detector: ShakeGestureDetector,
        from startTime: TimeInterval,
        amplitude: CGFloat = 20,
        segments: Int = 6,
        step: TimeInterval = 0.1
    ) -> TimeInterval {
        var t = startTime
        var x: CGFloat = 100
        detector.feed(CGPoint(x: x, y: 100), at: t)
        for i in 0..<segments {
            t += step
            x += (i % 2 == 0 ? amplitude : -amplitude)
            detector.feed(CGPoint(x: x, y: 100), at: t)
        }
        return t
    }

    /// 时间窗内 X 方向反转 ≥3 且振幅达标 → 触发一次
    func testShakeTriggersOnSufficientReversals() {
        var triggered: [CGPoint] = []
        let detector = makeDetector { triggered.append($0) }

        feedShake(detector, from: 0)

        XCTAssertEqual(triggered.count, 1)
    }

    /// 直线快速移动（无方向反转）→ 不触发
    func testStraightLineMovementDoesNotTrigger() {
        var triggered = false
        let detector = makeDetector { _ in triggered = true }

        var t = 0.0
        for i in 0..<12 {
            t += 0.05
            detector.feed(CGPoint(x: CGFloat(i) * 50, y: 100), at: t)
        }

        XCTAssertFalse(triggered)
    }

    /// 方向反转足够但振幅不足（小手抖）→ 不触发
    func testSmallJitterDoesNotTrigger() {
        var triggered = false
        let detector = makeDetector { _ in triggered = true }

        feedShake(detector, from: 0, amplitude: 3, segments: 8, step: 0.05)

        XCTAssertFalse(triggered)
    }

    /// 触发后 1s 冷却期内不再重复触发
    func testCooldownSuppressesImmediateRetrigger() {
        var count = 0
        let detector = makeDetector { _ in count += 1 }

        var t = feedShake(detector, from: 0)          // t ≈ 0.6，触发一次
        t = feedShake(detector, from: t)              // 0.7~1.2 处于冷却期（至 1.6）

        XCTAssertEqual(count, 1)
    }

    /// 采样超出 0.8s 时间窗后，旧的反转不计入 → 缓慢摆动不触发
    func testSlowSwingOutsideWindowDoesNotTrigger() {
        var triggered = false
        let detector = makeDetector { _ in triggered = true }

        feedShake(detector, from: 0, amplitude: 30, segments: 4, step: 0.5)

        XCTAssertFalse(triggered)
    }

    /// 功能开关关闭时全链路停用 → 不触发
    func testDisabledByFloatingNestSwitch() {
        Defaults[.floatingNestEnabled] = false
        var triggered = false
        let detector = ShakeGestureDetector()
        detector.onShake = { _ in triggered = true }

        feedShake(detector, from: 0)

        XCTAssertFalse(triggered)
    }
}
