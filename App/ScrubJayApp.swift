import AppKit
import SwiftUI

@main
struct ScrubJayApp: App {
  @State private var state = AppState()

  private static let websiteURL = URL(string: "https://scrubjay.openwhale.dev")!

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(state)
    }
    .windowResizability(.contentMinSize)
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("About ScrubJay") {
          NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
              string: "scrubjay.openwhale.dev",
              attributes: [.link: Self.websiteURL, .font: NSFont.systemFont(ofSize: 11)])
          ])
        }
      }
      CommandGroup(replacing: .help) {
        Button("ScrubJay Website") {
          NSWorkspace.shared.open(Self.websiteURL)
        }
      }
    }
  }
}
