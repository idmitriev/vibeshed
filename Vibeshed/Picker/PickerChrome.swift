import SwiftUI

extension View {
    /// The picker panel's background, edge and shadow. With the overlay up, a thin glass
    /// over the dimmed backdrop. Without it the picker sits straight on other windows and
    /// the desktop, so it goes near-solid, with a crisper edge and a deeper shadow.
    func pickerChrome(cornerRadius: CGFloat, backdropShown: Bool) -> some View {
        modifier(PickerChrome(cornerRadius: cornerRadius, backdropShown: backdropShown))
    }
}

private struct PickerChrome: ViewModifier {
    let cornerRadius: CGFloat
    let backdropShown: Bool
    @Environment(\.pickerTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// How much of what shows through the material the solid fill hides, without the overlay.
    private static let solidFillOpacity = 0.72

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius)
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    // The glass panels inside blur this too, so it evens them out as well.
                    shape.fill(theme.solidBackground ?? Color(nsColor: .windowBackgroundColor))
                        .opacity(backdropShown ? 0 : Self.solidFillOpacity)
                    if let tint = theme.backgroundTint {
                        shape.fill(tint)
                    }
                }
            }
            .clipShape(shape)
            .overlay { edge }
            .shadow(color: theme.shadowColor ?? .black.opacity(0.35), radius: 8, y: 2)
            // Reaches ~2 × radius + y, inside `PickerView.shadowMargin`.
            .shadow(color: backdropShown ? .clear : theme.shadowColor ?? .black.opacity(0.3), radius: 18, y: 8)
            // The overlay fades out under a live preview, and back in after.
            .animation(.easeInOut(duration: 0.25), value: backdropShown)
    }

    /// A faint hairline over the backdrop. Without it, a dark outline holds the edge
    /// against light backgrounds and a light inner rim against dark ones, as on macOS windows.
    @ViewBuilder private var edge: some View {
        if backdropShown {
            shape.stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        } else {
            ZStack {
                shape.inset(by: -1).strokeBorder(.black.opacity(isDark ? 0.55 : 0.18), lineWidth: 1)
                shape.strokeBorder(.white.opacity(isDark ? 0.22 : 0.6), lineWidth: 0.5)
            }
        }
    }
}
