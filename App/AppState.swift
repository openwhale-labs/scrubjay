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
  static let startupSelectionID = "scrubjay.startup"

  let helper = HelperClient()

  init() {
    // Coming back from System Settings after approving the helper should
    // reflect immediately.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.helper.refreshStatus()
      }
    }
  }

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
  /// Login items and daemons left behind by apps that are gone; nil until
  /// the helper has read the database.
  var staleBackgroundItems: [StaleBackgroundItem]?
  var backgroundItemsTotal = 0
  var isScanning = false
  var isRemoving = false
  var removalError: String?
  /// Set when trashing an app bundle failed on the App Management privacy
  /// setting; drives the alert that links to System Settings.
  var needsAppManagement = false
  /// Shown on the placeholder after a completed uninstall.
  var lastRemovalNote: String?
  /// Bundle IDs of currently running apps, for the sidebar lock badge.
  var runningBundleIDs: Set<String> = []
  /// Total footprint per app — bundle plus every matched leftover —
  /// computed in the background after the list loads.
  var appSizes: [String: Int64] = [:]
  private var sizeSweepGeneration = 0
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
    refreshRunningApps()
    sizeSweepGeneration += 1
    let sweep = sizeSweepGeneration
    let snapshot = apps
    Task {
      // Bundle sizes first: one directory walk each, so the sidebar has
      // numbers within a second rather than after a full-disk sweep.
      let bundleSizes = await Task.detached(priority: .utility) {
        Dictionary(
          uniqueKeysWithValues: snapshot.map {
            ($0.bundleID, FileSize.allocatedSize(at: $0.bundleURL) ?? 0)
          })
      }.value
      guard sweep == self.sizeSweepGeneration else { return }
      self.appSizes = bundleSizes

      // Then refine to the real footprint, app by app at low priority. This
      // scans every search root per app, so it must never block the list or
      // outlive the selection that started it.
      let identities = snapshot.map(\.identity)
      for app in snapshot {
        let total = await Task.detached(priority: .background) {
          let bundle = FileSize.allocatedSize(at: app.bundleURL) ?? 0
          let leftovers = LeftoverScanner.forCurrentUser()
            .scan(for: app.identity, amongInstalled: identities)
            .compactMap(\.sizeBytes)
            .reduce(0, +)
          return bundle + leftovers
        }.value
        guard sweep == self.sizeSweepGeneration else { return }
        self.appSizes[app.bundleID] = total
      }
    }
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
      staleBackgroundItems = nil
      await loadOrphans(generation: generation)
      return
    }
    if selectedBundleID == Self.startupSelectionID {
      devCaches = nil
      orphans = nil
      await loadBackgroundItems(generation: generation)
      return
    }
    devCaches = nil
    orphans = nil
    staleBackgroundItems = nil
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
    // The scan's snapshot may be minutes old — the user could have launched
    // the app since. Removing a running bundle leaves a half-deleted app.
    refreshRunningApps()
    if current.appBundleSelected, runningBundleIDs.contains(current.app.bundleID) {
      current.isAppRunning = true
      scan = current
      removalError = "\(current.app.name) is running. Quit it first."
      return
    }
    let generation = loadGeneration
    let plannedCount = current.selectedCount
    let plannedSize = current.selectedSize
    var bundleRemoved = false
    var failures: [String] = []
    isRemoving = true
    defer { isRemoving = false }

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
        agent.belongsTo(bundleID: current.app.bundleID) {
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
      bundleRemoved = await removeBundle(of: &current, failures: &failures)
      if bundleRemoved {
        await loadApps()
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

  /// Trash the app bundle itself. Returns true once the bundle is gone.
  private func removeBundle(of current: inout ScanResult, failures: inout [String]) async -> Bool {
    do {
      try Trasher.trash(current.app.bundleURL)
      current.appBundleSelected = false
      current.appBundleSize = nil
      return true
    } catch {
      // Root-owned bundles (Tunnelblick installs itself owned by root)
      // defeat a user-level trash; the helper can still move them.
      var helperMessage: String?
      if helper.status == .enabled {
        let helperFailures = await helper.trashSystemItems([current.app.bundleURL])
        if let message = helperFailures[current.app.bundleURL.path] {
          helperMessage = message
        } else {
          current.appBundleSelected = false
          current.appBundleSize = nil
          return true
        }
      }
      // A permission refusal on a bundle is the App Management privacy
      // setting — a raw error text would leave the user with no way
      // forward, so it gets its own alert with a settings link instead.
      if Trasher.isPermissionDenied(error) {
        needsAppManagement = true
      } else {
        let reason = helperMessage ?? error.localizedDescription
        failures.append("\(current.app.bundleURL.lastPathComponent): \(reason)")
      }
      return false
    }
  }

  /// Open System Settings on Privacy & Security › App Management. There is
  /// no SMAppService-style API for this pane, only the URL scheme.
  func openAppManagementSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")
    else { return }
    NSWorkspace.shared.open(url)
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

  /// Read the background item database through the helper and keep the
  /// entries whose app is gone.
  func loadBackgroundItems(generation: Int? = nil) async {
    let generation = generation ?? loadGeneration
    isScanning = true
    helper.refreshStatus()
    guard helper.status == .enabled else {
      isScanning = false
      staleBackgroundItems = nil
      backgroundItemsTotal = 0
      return
    }
    let dump = await helper.readBackgroundItems()
    let parsed = await Task.detached { dump.map(BackgroundItems.parse(dump:)) ?? [] }.value
    let stale = await Task.detached { BackgroundItems.stale(in: parsed) }.value
    guard generation == loadGeneration, selectedBundleID == Self.startupSelectionID else { return }
    isScanning = false
    backgroundItemsTotal = parsed.count
    staleBackgroundItems = stale
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
