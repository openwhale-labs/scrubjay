import Foundation

/// A well-known developer cache directory that is safe to clear: everything
/// in it is re-downloaded or rebuilt on demand. Locations that hold
/// irreplaceable data (Xcode archives, simulator devices, project
/// node_modules) are deliberately not in this catalog.
public struct DevCacheLocation: Sendable, Hashable, Identifiable {
  /// Stable slug used by the CLI, e.g. `npm`.
  public let id: String
  public let name: String
  /// What the cache holds and what happens after clearing.
  public let detail: String
  public let url: URL
}

/// The status of a catalog entry on this machine.
public struct DevCacheStatus: Sendable, Hashable, Identifiable {
  public var id: String { location.id }
  public let location: DevCacheLocation
  public let sizeBytes: Int64?
}

public enum DevCaches {
  /// All known cache locations under the given home directory.
  public static func catalog(home: URL) -> [DevCacheLocation] {
    func entry(_ id: String, _ name: String, _ detail: String, _ path: String) -> DevCacheLocation {
      DevCacheLocation(
        id: id, name: name, detail: detail,
        url: home.appendingPathComponent(path, isDirectory: true))
    }
    return [
      entry(
        "xcode-deriveddata", "Xcode DerivedData",
        "Build products and indexes; rebuilt on the next build.",
        "Library/Developer/Xcode/DerivedData"),
      entry(
        "simulator-caches", "Simulator caches",
        "CoreSimulator caches; devices and their data are untouched.",
        "Library/Developer/CoreSimulator/Caches"),
      entry(
        "swiftpm", "Swift Package Manager cache",
        "Package checkouts and manifests; re-fetched on demand.",
        "Library/Caches/org.swift.swiftpm"),
      entry(
        "npm", "npm cache",
        "Downloaded packages; re-fetched on install.",
        ".npm/_cacache"),
      entry(
        "pnpm", "pnpm store",
        "Content-addressable package store; re-fetched on install.",
        "Library/pnpm/store"),
      entry(
        "yarn", "Yarn cache",
        "Downloaded packages; re-fetched on install.",
        "Library/Caches/Yarn"),
      entry(
        "pip", "pip cache",
        "Downloaded wheels; re-fetched on install.",
        "Library/Caches/pip"),
      entry(
        "uv", "uv cache",
        "Downloaded wheels and builds; re-fetched on install.",
        "Library/Caches/uv"),
      entry(
        "cargo", "Cargo registry cache",
        "Downloaded crates; re-fetched on build.",
        ".cargo/registry/cache"),
      entry(
        "go-build", "Go build cache",
        "Compiled objects; rebuilt on the next build.",
        "Library/Caches/go-build"),
      entry(
        "homebrew", "Homebrew downloads",
        "Downloaded bottles and casks; re-fetched when needed.",
        "Library/Caches/Homebrew"),
      entry(
        "cocoapods", "CocoaPods cache",
        "Downloaded pods; re-fetched on install.",
        "Library/Caches/CocoaPods"),
      entry(
        "playwright", "Playwright browsers",
        "Downloaded browser builds; re-fetched by npx playwright install.",
        "Library/Caches/ms-playwright")
    ]
  }

  /// Catalog entries that exist on this machine, with sizes when requested.
  public static func present(home: URL? = nil, computeSizes: Bool = true) -> [DevCacheStatus] {
    let home = home ?? FileManager.default.homeDirectoryForCurrentUser
    return catalog(home: home).compactMap { location in
      guard FileManager.default.fileExists(atPath: location.url.path) else { return nil }
      return DevCacheStatus(
        location: location,
        sizeBytes: computeSizes ? FileSize.allocatedSize(at: location.url) : nil)
    }
  }
}
