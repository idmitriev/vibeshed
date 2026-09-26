import SwiftUI

/// Stack of keystroke chips, newest at the bottom.
struct KeystrokeOverlayView: View {
    let visualizer: KeystrokeVisualizer
    let themeEngine: ThemeEngine

    var body: some View {
        VStack(spacing: 8) {
            ForEach(visualizer.log.chips) { chip in
                KeystrokeChipView(chip: chip, accent: themeEngine.theme.accent)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(duration: 0.25), value: visualizer.log.chips)
        .environment(\.colorScheme, .dark)
    }
}

private struct KeystrokeChipView: View {
    let chip: KeystrokeChip
    let accent: Color

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(chip.text)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if chip.count > 1 {
                        Text("×\(chip.count)")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .contentTransition(.numericText())
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Self.shape.fill(.black.opacity(0.75)))
        .overlay(
            Self.shape.strokeBorder(
                chip.isVibeshed ? accent : .white.opacity(0.12),
                lineWidth: chip.isVibeshed ? 2 : 1
            )
        )
        .shadow(color: chip.isVibeshed ? accent.opacity(0.45) : .black.opacity(0.3), radius: 12)
    }

    private var icon: String? {
        switch chip.kind {
        case .binding: "sparkle"
        case .remap: "arrow.triangle.swap"
        case .typing, .combo: nil
        }
    }

    private var caption: String? {
        switch chip.kind {
        case let .binding(actionID): chip.caption ?? actionID.rawValue
        case let .remap(target): "Remapped to \(target)"
        case .typing, .combo: nil
        }
    }
}
