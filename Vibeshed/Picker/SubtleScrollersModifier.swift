import AppKit
import SwiftUI

extension View {
    func subtleScrollers() -> some View {
        background(SubtleScrollersConfigurator())
    }

    func scrollEdgeFade(top: CGFloat = 6, bottom: CGFloat = 12) -> some View {
        mask {
            VStack(spacing: 0) {
                if top > 0 {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: top)
                }

                Color.black

                if bottom > 0 {
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bottom)
                }
            }
        }
    }
}

private struct SubtleScrollersConfigurator: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        SubtleScrollersHostView()
    }

    func updateNSView(_: NSView, context _: Context) {}
}

private final class SubtleScrollersHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.applyStyle()
        }
    }

    private func applyStyle() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.verticalScroller?.alphaValue = 0.25
        scrollView.horizontalScroller?.controlSize = .mini
        scrollView.horizontalScroller?.alphaValue = 0.25
    }
}
