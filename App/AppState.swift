import AppKit
import Observation
import ScrubJayKit

/// One row in the removal checklist.
struct SelectableItem: Identifiable {
  let item: LeftoverItem
  var isSelected: Bool

  var id: URL { item.url }
}

/// The result of a completed scan, driving the detail pane.
struct ScanResult {
  let app: InstalledApp
  var appBundleSelected: Bool
  var appBundleSize: Int64?
  var items: [SelectableItem]
  var isAppRunning: Bool
  /// Set when Homebrew installed this app.
  var caskToken: String?
  /// True for apps whose data is irreplaceable history (chat archives).
  var holdsChatHistory: Bool

  var selectedCount: Int {
    items.count(where: \.isSelected) + (appBundleSelected ? 1 : 0)
  }

  var selectedSize: Int64 {
    let leftovers = items.filter(\.isSelected).compactMap(\.item.sizeBytes).reduce(0, +)
    return leftovers + (appBundleSelected ? (appBundleSize ?? 0) : 0)
  }
}

/// One row in the developer-caches checklist. Nothing is preselected.
struct SelectableCache: Identifiable {
  let status: DevCacheStatus
  var isSelected: Bool

  var id: String { status.id }
}

@MainActor
@Observable
final class AppState {
  /// Sidebar sentinels for the tool panes.
  static let devCachesSelectionID = "scrubjay.dev-caches"
  static let orphansSelectionID = "scrubjay.orphans"

  let helper = HelperClient()

  var apps: [InstalledApp] = []
  var query = ""
  var selectedBundleID: String?
  /// Monotonic token: every selection change starts a new generation, and
  /// only the newest generation may publish results or clear the spinner —
  /// a stale scan must never be shown for (or removed as) the current app.
  private var loadGeneration = 0
  var scan: ScanResult?
  var devCaches: [SelectableCache]?
  var orphans: [SelectableItem]?
  var isScanning = false
  var removalError: String?
  /// Shown on the placeholder after a completed uninstall.
  var lastRemovalNote: String?
  /// Bundle IDs of currently running apps, for the sidebar lock badge.
  var runningBundleIDs: Set<String> = []
  /// App bundle file names owned by Homebrew casks, for the sidebar badge.
  var caskAppNames: Set<String> = []
  /// App bundle sizes, computed in the background after the list loads.
  var appSizes: [String: Int64] = [:]
  /// Sidebar ordering: which key, and whether ascending. Clicking the active
  /// key in the UI flips the direction.
  var sidebarSortBySize = false
  var sidebarSortAscending = true

  var filteredApps: [InstalledApp] {
    var result = apps
    if !query.isEmpty {
      result = result.filter {
        $0.name.localizedCaseInsensitiveContains(query)
          || $0.bundleID.localizedCaseInsensitiveContains(query)
      }
    }
    if sidebarSortBySize {
      result.sort {
        let lhs = appSizes[$0.bundleID] ?? -1
        let rhs = appSizes[$1.bundleID] ?? -1
        return sidebarSortAscending ? lhs < rhs : lhs > rhs
      }
    } else if !sidebarSortAscending {
      result.reverse()
    }
    return result
  }

  /// Sort-header click: a new key starts at its natural direction
  /// (name A→Z, size largest first); clicking the active key flips it.
  func selectSidebarSort(bySize: Bool) {
    if sidebarSortBySize == bySize {
      sidebarSortAscending.toggle()
    } else {
      sidebarSortBySize = bySize
      sidebarSortAscending = !bySize
    }
  }

  func loadApps() async {
    apps = await Task.detached { AppInventory.discoverApps().filter { !$0.isAppleApp } }.value
    caskAppNames = Set(
      await Task.detached { Homebrew.installedCasks() }.value.flatMap(\.appNames))
    refreshRunningApps()
    let snapshot = apps
    appSizes = await Task.detached {
      Dictionary(
        uniqueKeysWithValues: snapshot.map {
          ($0.bundleID, FileSize.allocatedSize(at: $0.bundleURL) ?? 0)
        })
    }.value
  }

  func refreshRunningApps() {
    runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
  }

  func scanSelectedApp() async {
    loadGeneration += 1
    let generation = loadGeneration
    scan = nil
    if selectedBundleID != nil {
      lastRemovalNote = nil
    }
    if selectedBundleID == Self.devCachesSelectionID {
      orphans = nil
      await loadDevCaches(generation: generation)
      return
    }
    if selectedBundleID == Self.orphansSelectionID {
      devCaches = nil
      await loadOrphans(generation: generation)
      return
    }
    devCaches = nil
    orphans = nil
    guard let app = apps.first(where: { $0.bundleID == selectedBundleID }) else {
      return
    }
    isScanning = true

    let others = apps.map(\.identity)
    let (items, bundleSize, cask) = await Task.detached {
      let scanner = LeftoverScanner.forCurrentUser()
      let found = scanner.scan(for: app.identity, amongInstalled: others)
      let cask = Homebrew.caskToken(
        forAppNamed: app.bundleURL.lastPathComponent, in: Homebrew.installedCasks())
      return (found, FileSize.allocatedSize(at: app.bundleURL), cask)
    }.value

    guard generation == loadGeneration else { return }
    isScanning = false
    refreshRunningApps()
    helper.refreshStatus()
    let sensitive = SensitiveApps.holdsChatHistory(bundleID: app.bundleID)
    scan = ScanResult(
      app: app,
      appBundleSelected: true,
      appBundleSize: bundleSize,
      // Preselection is confidence-driven: `low` is never preselected. For
      // chat apps, data directories also start unselected — losing a cache
      // costs a re-download, losing chat history costs the history.
      items: items.map { item in
        var selected = item.confidence >= .medium
        if sensitive && SensitiveApps.dataKinds.contains(item.kind) {
          selected = false
        }
        return SelectableItem(item: item, isSelected: selected)
      },
      isAppRunning: Self.isRunning(bundleID: app.bundleID),
      caskToken: cask,
      holdsChatHistory: sensitive
    )
  }

  /// Move the selected items (and optionally the app bundle) to the Trash.
  func removeSelected() async {
    guard var current = scan else { return }
    // The removal plan must belong to the app the sidebar shows right now,
    // and Apple applications are never removed — same policy as the CLI.
    guard current.app.bundleID == selectedBundleID else { return }
    guard !current.app.isAppleApp else {
      removalError = "Apple applications cannot be removed."
      return
    }
    let generation = loadGeneration
    let plannedCount = current.selectedCount
    let plannedSize = current.selectedSize
    var bundleRemoved = false
    var failures: [String] = []

    // System-domain items go through the privileged helper.
    let systemEntries = current.items.filter {
      $0.isSelected && LeftoverCatalog.isSystemPath($0.item.url)
    }
    if !systemEntries.isEmpty {
      if helper.status == .enabled {
        let helperFailures = await helper.trashSystemItems(systemEntries.map(\.item.url))
        for entry in systemEntries {
          if let message = helperFailures[entry.item.url.path] {
            failures.append("\(entry.item.url.lastPathComponent): \(message)")
          } else {
            current.items.removeAll { $0.id == entry.id }
          }
        }
      } else {
        failures.append(
          "\(systemEntries.count) system items skipped — enable the ScrubJay helper first.")
      }
    }

    for entry in current.items where entry.isSelected && !LeftoverCatalog.isSystemPath(entry.item.url) {
      // Unloading is a behavior change beyond the Trash model: only do it
      // when the agent's own Label carries this app's bundle ID.
      if let agent = entry.item.launchAgent, agent.isLoaded,
        agent.belongsTo(bundleID: current.app.bundleID)
      {
        LaunchAgents.unload(label: agent.label)
      }
      do {
        try Trasher.trash(entry.item.url)
        current.items.removeAll { $0.id == entry.id }
      } catch {
        failures.append("\(entry.item.url.lastPathComponent): \(error.localizedDescription)")
      }
    }
    if current.appBundleSelected {
      do {
        try Trasher.trash(current.app.bundleURL)
        current.appBundleSelected = false
        current.appBundleSize = nil
        bundleRemoved = true
        await loadApps()
      } catch {
        failures.append("\(current.app.bundleURL.lastPathComponent): \(error.localizedDescription)")
      }
    }

    removalError = failures.isEmpty ? nil : failures.joined(separator: "\n")

    // A completed uninstall returns to the placeholder with a summary; the
    // app is gone from the sidebar.
    if bundleRemoved {
      let count = max(plannedCount - failures.count, 0)
      lastRemovalNote =
        "\(current.app.name) moved to the Trash — \(count) items, \(FileSize.format(plannedSize))."
      if generation == loadGeneration, current.app.bundleID == selectedBundleID {
        selectedBundleID = nil
        scan = nil
      }
      return
    }

    // The user may have moved on while removal ran.
    guard generation == loadGeneration, current.app.bundleID == selectedBundleID else { return }
    scan = current
  }

  func loadOrphans(generation: Int? = nil) async {
    let generation = generation ?? loadGeneration
    isScanning = true
    let installed = apps.map(\.identity)
    let found = await Task.detached {
      OrphanScanner.forCurrentUser()
        .scan(installed: installed + AppInventory.auxiliaryIdentities())
    }.value
    guard generation == loadGeneration, selectedBundleID == Self.orphansSelectionID else { return }
    isScanning = false
    // Orphans are never preselected.
    orphans = found.map { SelectableItem(item: $0, isSelected: false) }
  }

  /// Move selected orphaned leftovers to the Trash, then rescan.
  func cleanSelectedOrphans() async {
    guard let items = orphans else { return }
    var failures: [String] = []
    for entry in items where entry.isSelected {
      do {
        try Trasher.trash(entry.item.url)
      } catch {
        failures.append("\(entry.item.url.lastPathComponent): \(error.localizedDescription)")
      }
    }
    removalError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    await loadOrphans()
  }

  func loadDevCaches(generation: Int? = nil) async {
    let generation = generation ?? loadGeneration
    isScanning = true
    let present = await Task.detached { DevCaches.present() }.value
    guard generation == loadGeneration, selectedBundleID == Self.devCachesSelectionID else {
      return
    }
    isScanning = false
    devCaches = present
      .sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
      .map { SelectableCache(status: $0, isSelected: false) }
  }

  /// Move the selected caches to the Trash, then re-list.
  func cleanSelectedCaches() async {
    guard let caches = devCaches else { return }
    var failures: [String] = []
    for cache in caches where cache.isSelected {
      do {
        try Trasher.trash(cache.status.location.url)
      } catch {
        failures.append(
          "\(cache.status.location.name): \(error.localizedDescription)")
      }
    }
    removalError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    await loadDevCaches()
  }

  /// Select an app dropped onto the window. Returns false when the bundle
  /// cannot be identified or is not in the inventory yet.
  func selectApp(at url: URL) -> Bool {
    guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return false }
    // Same protection as everywhere else: Apple applications are off-limits,
    // including ones dragged in from /System/Applications.
    guard !bundleID.hasPrefix("com.apple.") else { return false }
    if !apps.contains(where: { $0.bundleID == bundleID }) {
      // An app from a location the inventory does not cover (e.g. a DMG).
      guard let app = AppInventory.readBundle(at: url) else { return false }
      apps.append(app)
      apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    selectedBundleID = bundleID
    return true
  }

  private static func isRunning(bundleID: String) -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
  }
}
