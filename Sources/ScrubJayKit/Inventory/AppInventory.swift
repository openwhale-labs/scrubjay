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

  /// Read a single app bundle, e.g. one dropped onto the window.
  public static func readBundle(at url: URL) -> InstalledApp? {
    guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
      return nil
    }
    let info = bundle.infoDictionary ?? [:]
    let name =
      (info["CFBundleDisplayName"] as? String)
      ?? (info["CFBundleName"] as? String)
      ?? url.deletingPathExtension().lastPathComponent
    let version = info["CFBundleShortVersionString"] as? String
    return InstalledApp(bundleID: bundleID, name: name, bundleURL: url, version: version)
  }
}
