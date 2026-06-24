import SwiftUI

// MARK: - List Item View

struct MathActionListItemView: View {
    let action: MathAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName ?? "equal.circle")
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("= \(action.formattedResult)")
                    .font(.body.monospacedDigit())
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(action.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("Copy")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        switch action.resultType {
        case .expression: .orange
        case .unitConversion: .blue
        case .currencyConversion: .green
        case .percentage: .pink
        case .baseConversion: .purple
        }
    }
}

// MARK: - Preview View

struct MathActionPreviewView: View {
    let action: MathAction

    var body: some View {
        PreviewLayout(moduleName: "math") {
            PreviewHeader(
                title: "= \(action.formattedResult)",
                subtitle: action.subtitle,
                systemIcon: action.iconName ?? "equal.circle",
                iconColor: headerColor
            )

            PreviewPill(text: typeName, icon: typeIcon, color: headerColor)

            ForEach(
                Array(action.detailLines.enumerated()),
                id: \.offset
            ) { _, detail in
                PreviewMetadataRow(
                    icon: "info.circle",
                    label: detail.label,
                    value: detail.value
                )
            }

            PreviewMetadataRow(
                icon: "doc.on.doc",
                label: "Action",
                value: "Press Enter to copy result"
            )
        }
    }

    private var headerColor: Color {
        switch action.resultType {
        case .expression: .orange
        case .unitConversion: .blue
        case .currencyConversion: .green
        case .percentage: .pink
        case .baseConversion: .purple
        }
    }

    private var typeName: String {
        switch action.resultType {
        case .expression: "Expression"
        case .unitConversion: "Unit Conversion"
        case .currencyConversion: "Currency"
        case .percentage: "Percentage"
        case .baseConversion: "Base Conversion"
        }
    }

    private var typeIcon: String {
        switch action.resultType {
        case .expression: "function"
        case .unitConversion: "arrow.left.arrow.right"
        case .currencyConversion: "dollarsign.circle"
        case .percentage: "percent"
        case .baseConversion: "number"
        }
    }
}
