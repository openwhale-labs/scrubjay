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
          Label("Orphaned leftovers", systemImage: "questionmark.folder")
            .tag(AppState.orphansSelectionID)
        }
        Section {
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
              Spacer()
              if let size = state.appSizes[app.bundleID] {
                Text(FileSize.format(size))
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
              }
              if state.caskAppNames.contains(app.bundleURL.lastPathComponent) {
                Image(systemName: "shippingbox")
                  .foregroundStyle(.secondary)
                  .help("Installed via Homebrew")
              }
              if state.runningBundleIDs.contains(app.bundleID) {
                Image(systemName: "lock.fill")
                  .foregroundStyle(.secondary)
                  .help("Running — quit before uninstalling")
              }
            }
            .tag(app.bundleID)
          }
        } header: {
          HStack {
            Text("Applications")
            Spacer()
            sortHeader("Name", bySize: false)
            sortHeader("Size", bySize: true)
          }
          .padding(.trailing, 8)
          .padding(.bottom, 6)
        }
      }
      .searchable(text: $state.query, placement: .sidebar, prompt: "Search apps")
      .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    } detail: {
      if state.selectedBundleID == AppState.devCachesSelectionID {
        DevCachesView()
      } else if state.selectedBundleID == AppState.orphansSelectionID {
        OrphansView()
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

  /// A clickable sort key: click to activate, click again to flip direction.
  private func sortHeader(_ title: String, bySize: Bool) -> some View {
    Button {
      state.selectSidebarSort(bySize: bySize)
    } label: {
      HStack(spacing: 2) {
        Text(title)
        if state.sidebarSortBySize == bySize {
          Image(systemName: state.sidebarSortAscending ? "chevron.up" : "chevron.down")
            .font(.system(size: 8, weight: .bold))
        }
      }
      .font(.caption)
      .foregroundStyle(state.sidebarSortBySize == bySize ? .primary : .secondary)
    }
    .buttonStyle(.plain)
  }
}
