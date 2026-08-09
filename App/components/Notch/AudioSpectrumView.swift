//
//  AudioSpectrumView.swift
//  DropNest
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//  Extracted from MusicVisualizer.swift during feature trim (2026-08-07).
//
import AppKit
import Cocoa
import SwiftUI

class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = true
    // nonisolated(unsafe)：NSView 子类隐式 @MainActor，animationTimer 仅在 MainActor 的
    // startAnimating/stopAnimating 中读写、nonisolated deinit 中 invalidate。
    // 标 nonisolated(unsafe) 允许 deinit 安全访问
    // （参照 DragDetector.swift 的 mouseDownMonitor 范式）。
    private nonisolated(unsafe) var animationTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    deinit {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func setupBars() {
        let barWidth: CGFloat = 2
        let barCount = 4
        let spacing: CGFloat = barWidth
        let totalWidth = CGFloat(barCount) * (barWidth + spacing)
        let totalHeight: CGFloat = 14
        frame.size = CGSize(width: totalWidth, height: totalHeight)

        for i in 0 ..< barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.fillColor = NSColor.white.cgColor
            barLayer.backgroundColor = NSColor.white.cgColor
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            let path = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: totalHeight),
                                    xRadius: barWidth / 2,
                                    yRadius: barWidth / 2)
            barLayer.path = path.cgPath
            barLayers.append(barLayer)
            barScales.append(0.35)
            layer?.addSublayer(barLayer)
        }
    }

    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            // Timer block 是 nonisolated 上下文，调用 NSView 的 @MainActor 方法需 Task hop
            // （参照 ClipboardMonitor.swift 的 Timer 范式）
            Task { @MainActor in self?.updateBars() }
        }
        if let timer = animationTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }

    private func updateBars() {
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale = CGFloat.random(in: 0.35 ... 1.0)
            barScales[i] = targetScale
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = currentScale
            animation.toValue = targetScale
            animation.duration = 0.3
            animation.autoreverses = true
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            if #available(macOS 13.0, *) {
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 24, preferred: 24)
            }
            barLayer.add(animation, forKey: "scaleY")
        }
    }

    private func resetBars() {
        for (i, barLayer) in barLayers.enumerated() {
            barLayer.removeAllAnimations()
            barLayer.transform = CATransform3DMakeScale(1, 0.35, 1)
            barScales[i] = 0.35
        }
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}

struct AudioSpectrumView: NSViewRepresentable {
    @Binding var isPlaying: Bool

    func makeNSView(context: Context) -> AudioSpectrum {
        let spectrum = AudioSpectrum()
        spectrum.setPlaying(isPlaying)
        return spectrum
    }

    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: .constant(true))
        .frame(width: 16, height: 20)
        .padding()
}
