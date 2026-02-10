import SwiftUI

struct ResultView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: title == "Error" ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(title == "Error" ? .red : .green)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("Press Return to dismiss")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
