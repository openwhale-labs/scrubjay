import Foundation

/// Categories of places where apps leave files behind.
public enum LeftoverKind: String, Sendable, CaseIterable {
  case applicationSupport = "Application Support"
  case caches = "Caches"
  case preferences = "Preferences"
  case byHostPreferences = "Preferences (ByHost)"
  case containers = "Containers"
  case groupContainers = "Group Containers"
  case savedState = "Saved Application State"
  case httpStorages = "HTTP Storages"
  case webKit = "WebKit"
  case logs = "Logs"
  case launchAgents = "Launch Agents"
  case applicationScripts = "Application Scripts"
  case cookies = "Cookies"
  case recentDocuments = "Recent Documents"
  case launchDaemons = "Launch Daemons"
  case privilegedHelpers = "Privileged Helper Tools"
}

/// A directory whose top-level entries are matched against an app identity.
public struct SearchRoot: Sendable, Hashable {
  public let kind: LeftoverKind
  public let url: URL

  public init(kind: LeftoverKind, url: URL) {
    self.kind = kind
    self.url = url
  }
}

/// The catalog of search roots ScrubJay knows about.
public enum LeftoverCatalog {
  /// User-level roots under the given home directory.
  ///
  /// - Parameter home: injected for testability; pass a fixture directory in
  ///   tests and `FileManager.default.homeDirectoryForCurrentUser` in production.
  public static func userRoots(home: URL) -> [SearchRoot] {
    let library = home.appendingPathComponent("Library", isDirectory: true)
    func root(_ kind: LeftoverKind, _ path: String) -> SearchRoot {
      SearchRoot(kind: kind, url: library.appendingPathComponent(path, isDirectory: true))
    }
    return [
      root(.applicationSupport, "Application Support"),
      root(.caches, "Caches"),
      root(.preferences, "Preferences"),
      root(.byHostPreferences, "Preferences/ByHost"),
      root(.containers, "Containers"),
      root(.groupContainers, "Group Containers"),
      root(.savedState, "Saved Application State"),
      root(.httpStorages, "HTTPStorages"),
      root(.webKit, "WebKit"),
      root(.logs, "Logs"),
      root(.launchAgents, "LaunchAgents"),
      root(.applicationScripts, "Application Scripts"),
      root(.cookies, "Cookies"),
      root(
        .recentDocuments,
        "Application Support/com.apple.sharedfilelist/"
          + "com.apple.LSSharedFileList.ApplicationRecentDocuments"),
    ]
  }

  /// System-domain roots under /Library. Reading them needs no privileges;
  /// removing their items goes through the privileged helper.
  public static func systemRoots() -> [SearchRoot] {
    func root(_ kind: LeftoverKind, _ path: String) -> SearchRoot {
      SearchRoot(kind: kind, url: URL(fileURLWithPath: "/Library/\(path)", isDirectory: true))
    }
    return [
      root(.applicationSupport, "Application Support"),
      root(.caches, "Caches"),
      root(.preferences, "Preferences"),
      root(.launchAgents, "LaunchAgents"),
      root(.launchDaemons, "LaunchDaemons"),
      root(.privilegedHelpers, "PrivilegedHelperTools"),
    ]
  }

  /// True for items that live in the system domain and need the helper to
  /// remove.
  public static func isSystemPath(_ url: URL) -> Bool {
    url.standardizedFileURL.path.hasPrefix("/Library/")
  }
}
