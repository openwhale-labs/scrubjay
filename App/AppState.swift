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

  var selectedCount: Int {
    items.count(where: \.isSelected) + (appBundleSelected ? 1 : 0)
  }

  var selectedSize: Int64 {
    let leftovers = items.filter(\.isSelected).compactMap(\.item.sizeBytes).reduce(0, +)
    return leftovers + (appBundleSelected ? (appBundleSize ?? 0) : 0)
  }
}

@MainActor
@Observable
final class AppState {
  var apps: [InstalledApp] = []
  var query = ""
  var selectedBundleID: String?
  var scan: ScanResult?
  var isScanning = false
  var removalError: String?

  var filteredApps: [InstalledApp] {
    guard !query.isEmpty else { return apps }
    return apps.filter {
      $0.name.localizedCaseInsensitiveContains(query)
        || $0.bundleID.localizedCaseInsensitiveContains(query)
    }
  }

  func loadApps() async {
    apps = await Task.detached { AppInventory.discoverApps().filter { !$0.isAppleApp } }.value
  }

  func scanSelectedApp() async {
    guard let app = apps.first(where: { $0.bundleID == selectedBundleID }) else {
      scan = nil
      return
    }
    isScanning = true
    defer { isScanning = false }

    let others = apps.map(\.identity)
    let (items, bundleSize, cask) = await Task.detached {
      let scanner = LeftoverScanner.forCurrentUser()
      let found = scanner.scan(for: app.identity, amongInstalled: others)
      let cask = Homebrew.caskToken(
        forAppNamed: app.bundleURL.lastPathComponent, in: Homebrew.installedCasks())
      return (found, FileSize.allocatedSize(at: app.bundleURL), cask)
    }.value

    guard app.bundleID == selectedBundleID else { return }
    scan = ScanResult(
      app: app,
      appBundleSelected: true,
      appBundleSize: bundleSize,
      // Preselection is confidence-driven: `low` is never preselected.
      items: items.map { SelectableItem(item: $0, isSelected: $0.confidence >= .medium) },
      isAppRunning: Self.isRunning(bundleID: app.bundleID),
      caskToken: cask
    )
  }

  /// Move the selected items (and optionally the app bundle) to the Trash.
  func removeSelected() async {
    guard var current = scan else { return }
    var failures: [String] = []

    for entry in current.items where entry.isSelected {
      if let agent = entry.item.launchAgent, agent.isLoaded {
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
        await loadApps()
      } catch {
        failures.append("\(current.app.bundleURL.lastPathComponent): \(error.localizedDescription)")
      }
    }

    scan = current
    removalError = failures.isEmpty ? nil : failures.joined(separator: "\n")
  }

  /// Select an app dropped onto the window. Returns false when the bundle
  /// cannot be identified or is not in the inventory yet.
  func selectApp(at url: URL) -> Bool {
    guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return false }
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
