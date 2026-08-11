import AppKit
import SwiftUI

/// A shell command shown as monospaced text with a copy button, so the user
/// sees exactly what lands on the clipboard. The button turns into a green
/// checkmark for a moment after copying.
struct CommandChip: View {
  let command: String
  @State private var copied = false

  var body: some View {
    HStack(spacing: 6) {
      Text(command)
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        .textSelection(.enabled)
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task {
          try? await Task.sleep(for: .seconds(2))
          withAnimation(.easeOut(duration: 0.3)) { copied = false }
        }
      } label: {
        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
          .foregroundStyle(copied ? Color.green : Color.secondary)
          .contentTransition(.symbolEffect(.replace))
      }
      .buttonStyle(.plain)
      .help(copied ? "Copied" : "Copy command")
    }
  }
}
