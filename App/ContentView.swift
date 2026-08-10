import AppKit
import ScrubJayKit
import SwiftUI

struct ContentView: View {
  @Environment(AppState.self) private var state

  var body: some View {
    @Bindable var state = state
    NavigationSplitView {
      List(selection: $state.selectedBundleID) {
        Section {
          Label("Developer caches", systemImage: "hammer")
            .tag(AppState.devCachesSelectionID)
        }
        Section("Applications") {
          ForEach(state.filteredApps) { app in
            HStack(spacing: 8) {
              Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable()
                .frame(width: 28, height: 28)
              VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                Text(app.bundleID)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            .tag(app.bundleID)
          }
        }
      }
      .searchable(text: $state.query, placement: .sidebar, prompt: "Search apps")
      .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    } detail: {
      if state.selectedBundleID == AppState.devCachesSelectionID {
        DevCachesView()
      } else if state.isScanning {
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
    .dropDestination(for: URL.self) { urls, _ in
      guard let url = urls.first(where: { $0.pathExtension == "app" }) else { return false }
      return state.selectApp(at: url)
    }
    .task { await state.loadApps() }
    .onChange(of: state.selectedBundleID) {
      Task { await state.scanSelectedApp() }
    }
  }
}
