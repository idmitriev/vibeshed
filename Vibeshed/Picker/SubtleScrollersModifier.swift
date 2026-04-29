import AppKit
import SwiftUI

extension View {
    func subtleScrollers() -> some View {
        background(SubtleScrollersConfigurator())
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
        scrollView.verticalScroller?.alphaValue = 0.5
        scrollView.horizontalScroller?.alphaValue = 0.5
    }
}
