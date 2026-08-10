import ScrubJayKit
import SwiftUI

struct ContentView: View {
  @Environment(AppState.self) private var state

  var body: some View {
    @Bindable var state = state
    NavigationSplitView {
      List(state.filteredApps, selection: $state.selectedBundleID) { app in
        VStack(alignment: .leading, spacing: 2) {
          Text(app.name)
          Text(app.bundleID)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(app.bundleID)
      }
      .searchable(text: $state.query, placement: .sidebar, prompt: "Search apps")
      .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    } detail: {
      if state.isScanning {
        ProgressView("Scanning…")
      } else if state.scan != nil {
        DetailView()
      } else {
        ContentUnavailableView(
          "Select an app", systemImage: "sparkles",
          description: Text("Pick an app to see what it would leave behind."))
      }
    }
    .frame(minWidth: 720, minHeight: 460)
    .task { await state.loadApps() }
    .onChange(of: state.selectedBundleID) {
      Task { await state.scanSelectedApp() }
    }
  }
}
