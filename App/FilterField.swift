import SwiftUI

/// The one filter-input style used everywhere: magnifier, rounded field,
/// and a clear button that appears while text is present.
struct FilterField: View {
  let prompt: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: Theme.Space.xs) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Theme.Palette.secondaryText)
      TextField(prompt, text: $text)
        .textFieldStyle(.plain)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(Theme.Palette.secondaryText)
        }
        .buttonStyle(.plain)
        .help("Clear")
      }
    }
    .padding(.horizontal, Theme.Space.sm)
    .padding(.vertical, Theme.Space.xs)
    .background(Theme.Palette.chipFill, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
  }
}
