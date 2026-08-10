import SwiftUI

@main
struct ScrubJayApp: App {
  @State private var state = AppState()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(state)
    }
    .windowResizability(.contentMinSize)
  }
}
