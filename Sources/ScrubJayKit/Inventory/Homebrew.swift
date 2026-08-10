import Foundation

/// A Homebrew cask with the app bundles it installed.
public struct CaskInstall: Sendable, Hashable {
  public let token: String
  /// App bundle file names, e.g. `["Ice.app"]`.
  public let appNames: [String]

  public init(token: String, appNames: [String]) {
    self.token = token
    self.appNames = appNames
  }
}

/// Detects apps installed through Homebrew casks — filesystem only, brew is
/// never executed. A GUI cask keeps `<Caskroom>/<token>/<version>/<App>.app`
/// (a symlink to the installed app), which maps app names to cask tokens.
///
/// ScrubJay does not delegate removal to `brew uninstall`: that deletes
/// permanently, and ScrubJay only ever moves files to the Trash. Instead the
/// cask token is surfaced so the user can clear Homebrew's records afterwards.
public enum Homebrew {
  /// Caskroom locations that exist on this machine (Apple Silicon and Intel).
  public static func caskroomRoots() -> [URL] {
    ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
      .map { URL(fileURLWithPath: $0, isDirectory: true) }
      .filter { FileManager.default.fileExists(atPath: $0.path) }
  }

  /// Enumerate installed casks and the app bundles they own.
  public static func installedCasks(roots: [URL]? = nil) -> [CaskInstall] {
    let fm = FileManager.default
    var casks: [CaskInstall] = []
    for root in roots ?? caskroomRoots() {
      guard
        let tokens = try? fm.contentsOfDirectory(
          at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
      else { continue }
      for tokenDir in tokens {
        guard
          let versions = try? fm.contentsOfDirectory(
            at: tokenDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { continue }
        var appNames: Set<String> = []
        for versionDir in versions {
          let entries = (try? fm.contentsOfDirectory(
            at: versionDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
          for entry in entries where entry.pathExtension == "app" {
            appNames.insert(entry.lastPathComponent)
          }
        }
        if !appNames.isEmpty {
          casks.append(CaskInstall(token: tokenDir.lastPathComponent, appNames: appNames.sorted()))
        }
      }
    }
    return casks.sorted { $0.token < $1.token }
  }

  /// The cask that installed the given app bundle, if any.
  public static func caskToken(forAppNamed appName: String, in casks: [CaskInstall]) -> String? {
    casks.first { $0.appNames.contains(appName) }?.token
  }
}
