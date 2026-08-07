import SwiftUI
import Defaults

/// 展开态 HUD，在 NotchHeader 右侧显示胶囊状音量/亮度进度条。
struct OpenNotchHUD: View {
    @EnvironmentObject var vm: NotchViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Default(.showOpenNotchHUDPercentage) var showPercentage

    var body: some View {
        HStack(spacing: 8) {
            // 图标
            Group {
                switch type {
                case .volume:
                    if icon.isEmpty {
                        Image(systemName: SpeakerSymbol(value))
                            .contentTransition(.interpolate)
                    } else {
                        Image(systemName: icon)
                            .contentTransition(.interpolate)
                    }
                case .brightness:
                    Image(systemName: "sun.max.fill")
                        .contentTransition(.symbolEffect)
                case .backlight:
                    Image(systemName: value > 0.5 ? "light.max" : "light.min")
                        .contentTransition(.interpolate)
                default:
                    EmptyView()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 20, alignment: .center)

            // 进度条
            DraggableProgressBar(value: $value, onChange: { newVal in
                updateSystemValue(newVal)
            })
            .frame(width: showPercentage ? 65 : 108)

            // 百分比
            if showPercentage {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .frame(width: 35, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch value {
        case 0: return "speaker.slash"
        case 0...0.33: return "speaker.wave.1"
        case 0.33...0.66: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    func updateSystemValue(_ newVal: CGFloat) {
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newVal))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newVal))
        case .backlight:
            KeyboardBacklightManager.shared.setAbsolute(value: Float32(newVal))
        default:
            break
        }
    }
}
