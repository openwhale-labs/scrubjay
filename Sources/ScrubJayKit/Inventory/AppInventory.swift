import Foundation

/// Discovers installed application bundles.
public enum AppInventory {
  /// Default locations searched for `.app` bundles.
  public static func defaultDirectories() -> [URL] {
    [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true),
    ]
  }

  /// Enumerate app bundles in the given directories (one folder level deep,
  /// so `/Applications/Utilities` is covered without descending into bundles).
  public static func discoverApps(in directories: [URL]? = nil) -> [InstalledApp] {
    let fm = FileManager.default
    var apps: [InstalledApp] = []
    var seen: Set<String> = []

    for directory in directories ?? defaultDirectories() {
      guard
        let entries = try? fm.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])
      else {
        continue
      }
      for entry in entries {
        if entry.pathExtension == "app" {
          if let app = readBundle(at: entry), seen.insert(app.bundleID).inserted {
            apps.append(app)
          }
        } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
          // One level of subfolders, e.g. /Applications/Utilities.
          let nested = (try? fm.contentsOfDirectory(
            at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
          for sub in nested where sub.pathExtension == "app" {
            if let app = readBundle(at: sub), seen.insert(app.bundleID).inserted {
              apps.append(app)
            }
          }
        }
      }
    }
    return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  /// Places where live, app-like bundles exist outside the Applications
  /// folders: input methods, preference panes, screen savers, QuickLook and
  /// Spotlight plugins. Their files must never be mistaken for orphans.
  public static func auxiliaryBundleDirectories() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let subpaths = [
      "Input Methods", "PreferencePanes", "Screen Savers", "QuickLook", "Spotlight",
    ]
    return subpaths.flatMap { sub in
      [
        URL(fileURLWithPath: "/Library/\(sub)", isDirectory: true),
        home.appendingPathComponent("Library/\(sub)", isDirectory: true),
      ]
    }
  }

  /// Identities of auxiliary bundles (any bundle type with an Info.plist).
  /// These claim leftovers in the orphan scan but are not listed as
  /// uninstallable apps.
  public static func auxiliaryIdentities(in directories: [URL]? = nil) -> [AppIdentity] {
    let fm = FileManager.default
    var identities: [AppIdentity] = []
    for directory in directories ?? auxiliaryBundleDirectories() {
      let entries = (try? fm.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
      for entry in entries {
        if let app = readBundle(at: entry) {
          identities.append(app.identity)
        }
      }
    }
    return identities
  }

  /// Read a single app bundle, e.g. one dropped onto the window.
  public static func readBundle(at url: URL) -> InstalledApp? {
    guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
      return nil
    }
    let info = bundle.infoDictionary ?? [:]
    // Display what Finder displays: the (localized) file name. Info.plist
    // names still matter — leftover directories are often keyed by them
    // ("Code" for Visual Studio Code) — so they join the identity as
    // alternate names.
    let name = FileManager.default.displayName(atPath: url.path)
      .replacingOccurrences(of: ".app", with: "")
    let altNames = [info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String]
      .compactMap { $0 }
      .filter { $0 != name }
    let version = info["CFBundleShortVersionString"] as? String
    return InstalledApp(
      bundleID: bundleID, name: name, altNames: Array(Set(altNames)).sorted(),
      bundleURL: url, version: version)
  }
}
