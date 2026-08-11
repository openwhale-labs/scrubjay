import AppKit
import Sparkle
import SwiftUI

@main
struct ScrubJayApp: App {
  @State private var state = AppState()
  private let updater = SPUStandardUpdaterController(
    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

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
        Button("Check for Updates…") {
          updater.updater.checkForUpdates()
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
