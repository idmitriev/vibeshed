import AppKit
import SwiftUI

struct SearchFieldPill: Identifiable {
    let id: String
    let title: String
    let iconSystemName: String?
    let detail: String?
}

struct PickerSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search actions..."
    var pills: [SearchFieldPill] = []
    var onRemovePill: ((SearchFieldPill) -> Void)?
    var onBackspaceEmpty: (() -> Void)?
    @Environment(\.vibeTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(theme.iconTint ?? .secondary)

            ForEach(pills) { pill in
                PillView(pill: pill) {
                    onRemovePill?(pill)
                }
            }

            BackspaceTextField(
                text: $text,
                placeholder: placeholder,
                hasPills: !pills.isEmpty,
                onBackspaceEmpty: onBackspaceEmpty
            )
            .accessibilityIdentifier("pickerSearchField")
        }
    }
}

// MARK: - NSViewRepresentable TextField with backspace-on-empty detection

/// Custom NSTextField cell that provides our field editor.
private final class BackspaceTextFieldCell: NSTextFieldCell {
    let customFieldEditor = BackspaceAwareTextView()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        customFieldEditor.isFieldEditor = true
        return customFieldEditor
    }
}

/// Custom NSTextView (field editor) that intercepts backspace on empty text.
private final class BackspaceAwareTextView: NSTextView {
    var onBackspaceEmpty: (() -> Void)?

    override func deleteBackward(_ sender: Any?) {
        if string.isEmpty {
            onBackspaceEmpty?()
        } else {
            super.deleteBackward(sender)
        }
    }
}

private struct BackspaceTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var hasPills: Bool
    var onBackspaceEmpty: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let cell = BackspaceTextFieldCell()
        cell.isEditable = true
        cell.isSelectable = true
        cell.isBordered = false
        cell.drawsBackground = false
        cell.focusRingType = .none
        cell.isScrollable = true
        cell.wraps = false
        cell.lineBreakMode = .byClipping
        cell.placeholderString = placeholder
        cell.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large) + 2)

        let field = NSTextField(frame: .zero)
        field.cell = cell
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = cell.font
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator

        cell.customFieldEditor.onBackspaceEmpty = hasPills ? onBackspaceEmpty : nil
        cell.customFieldEditor.isRichText = false
        cell.customFieldEditor.font = cell.font

        // Focus after show animation completes (~300ms) to avoid layout during animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        if let cell = field.cell as? BackspaceTextFieldCell {
            cell.customFieldEditor.onBackspaceEmpty = hasPills ? onBackspaceEmpty : nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }
    }
}

// MARK: - PillView

private struct PillView: View {
    let pill: SearchFieldPill
    let onRemove: () -> Void
    @Environment(\.vibeTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: pill.iconSystemName ?? "sparkle")
                .font(.caption)
                .foregroundStyle(theme.iconTint ?? .secondary)

            Text(pill.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)

            if let detail = pill.detail {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(theme.selectionHighlight)
        )
    }
}
