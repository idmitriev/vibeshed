import SwiftUI

struct PickerSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search actions..."
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isFocused)
                .accessibilityIdentifier("pickerSearchField")
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isFocused = true
                    }
                }
                .onChange(of: text) {
                    // Re-grab focus if lost
                    if !isFocused {
                        isFocused = true
                    }
                }
        }
    }
}
