import AppKit
import SwiftUI

/// A small magnifier that reveals the file in Finder — so the user can look
/// at what a row actually contains before deciding to remove it.
struct RevealButton: View {
  let url: URL

  var body: some View {
    Button {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } label: {
      Image(systemName: "magnifyingglass.circle")
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .help("Show in Finder")
  }
}
