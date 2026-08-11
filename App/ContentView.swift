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
          Label("Startup items", systemImage: "power")
            .tag(AppState.startupSelectionID)
        }
        Section {
          ForEach(Array(state.filteredApps.enumerated()), id: \.element.id) { index, app in
            HStack(spacing: Theme.Space.md) {
              Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                .resizable()
                .frame(width: Theme.IconSize.sidebar, height: Theme.IconSize.sidebar)
              VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.sm) {
                  Text(app.name)
                  // Dock-style running dot; green = alive, the detail pane's
                  // orange banner carries the "quit first" warning.
                  if state.runningBundleIDs.contains(app.bundleID) {
                    Circle()
                      .fill(Theme.Palette.running)
                      .overlay(Circle().stroke(Theme.Palette.dotRing, lineWidth: 0.5))
                      .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                      .help("Running — quit before uninstalling")
                  }
                }
                Text(app.bundleID)
                  .font(.caption)
                  .foregroundStyle(Theme.Palette.secondaryText)
              }
              Spacer()
              if let size = state.appSizes[app.bundleID] {
                Text(FileSize.format(size))
                  .font(.caption)
                  .foregroundStyle(Theme.Palette.secondaryText)
                  .monospacedDigit()
                  .help("App plus everything it left behind")
              }
            }
            .tag(app.bundleID)
            // Hand-rolled zebra striping, applications only: the system
            // alternating API paints tool rows too.
            .listRowBackground(
              index.isMultiple(of: 2)
                ? Color.clear : Theme.Palette.rowStripe)
          }
        } header: {
          HStack {
            Text("Applications")
            Spacer()
            sortHeader("Name", bySize: false)
            sortHeader("Size", bySize: true)
          }
          .padding(.trailing, Theme.Space.xl)
          .padding(.bottom, Theme.Space.sm)
        }
      }
      .searchable(text: $state.query, placement: .sidebar, prompt: "Search apps")
      .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    } detail: {
      if state.selectedBundleID == AppState.devCachesSelectionID {
        DevCachesView()
      } else if state.selectedBundleID == AppState.orphansSelectionID {
        OrphansView()
      } else if state.selectedBundleID == AppState.startupSelectionID {
        StartupItemsView()
      } else if state.isScanning {
        ProgressView("Scanning…")
      } else if state.scan != nil {
        DetailView()
      } else if let note = state.lastRemovalNote {
        ContentUnavailableView(
          "Moved to Trash", systemImage: "checkmark.circle",
          description: Text(note + " Restore anytime from the Trash."))
      } else {
        ContentUnavailableView(
          "Select an app", systemImage: "sparkles",
          description: Text("Pick an app to see what it would leave behind."))
      }
    }
    .frame(minWidth: 720, minHeight: 460)
    // Every pane writes failures to the same place, so the alert lives
    // outside the split view rather than in one detail pane.
    .alert(
      "Some items could not be moved to the Trash",
      isPresented: .init(
        get: { state.removalError != nil },
        set: { if !$0 { state.removalError = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(state.removalError ?? "")
    }
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
        // Always present so activating a header never shifts the layout.
        Image(systemName: state.sidebarSortAscending ? "chevron.up" : "chevron.down")
          .font(.system(size: 8, weight: .bold))
          .opacity(state.sidebarSortBySize == bySize ? 1 : 0)
      }
      .font(.caption)
      .foregroundStyle(state.sidebarSortBySize == bySize ? .primary : .secondary)
    }
    .buttonStyle(.plain)
  }
}
