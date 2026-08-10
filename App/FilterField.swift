import SwiftUI

/// The one filter-input style used everywhere: magnifier, rounded field,
/// and a clear button that appears while text is present.
struct FilterField: View {
  let prompt: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(prompt, text: $text)
        .textFieldStyle(.plain)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear")
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
  }
}
