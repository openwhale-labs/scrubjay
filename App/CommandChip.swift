import AppKit
import SwiftUI

/// A shell command shown as monospaced text with a copy button, so the user
/// sees exactly what lands on the clipboard. The button turns into a green
/// checkmark for a moment after copying.
///
/// Every colour and size comes from `Theme`, and none of them are
/// hierarchical styles, so the chip looks identical wherever it is placed —
/// including inside a container that has set its own `foregroundStyle`.
struct CommandChip: View {
  let command: String
  @State private var copied = false

  var body: some View {
    HStack(spacing: Theme.Space.sm) {
      Text(command)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(Theme.Palette.secondaryText)
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.Palette.chipFill, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .textSelection(.enabled)
      Button(action: copy) {
        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
          .foregroundStyle(copied ? Theme.Palette.confirmation : Theme.Palette.secondaryText)
          .contentTransition(.symbolEffect(.replace))
      }
      .buttonStyle(.plain)
      .help(copied ? "Copied" : "Copy command")
    }
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(command, forType: .string)
    withAnimation(.easeOut(duration: 0.15)) { copied = true }
    Task {
      try? await Task.sleep(for: Theme.confirmationDuration)
      withAnimation(.easeOut(duration: 0.3)) { copied = false }
    }
  }
}
