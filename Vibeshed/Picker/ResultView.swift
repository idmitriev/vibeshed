import SwiftUI

struct ResultView: View {
    let title: String
    let message: String
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: title == "Error" ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(title == "Error" ? .red : .green)
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)

            Text(title)
                .font(.headline)
                .opacity(appeared ? 1 : 0)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .opacity(appeared ? 1 : 0)

            Text("Press Return to dismiss")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .opacity(appeared ? 1 : 0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}
