import Foundation

/// Scans search roots for files belonging to an app.
public struct LeftoverScanner: Sendable {
  public let roots: [SearchRoot]

  public init(roots: [SearchRoot]) {
    self.roots = roots
  }

  /// Convenience scanner over the current user's Library.
  public static func forCurrentUser() -> LeftoverScanner {
    LeftoverScanner(
      roots: LeftoverCatalog.userRoots(home: FileManager.default.homeDirectoryForCurrentUser))
  }

  /// Scan all roots for entries matching the app identity.
  ///
  /// Only the top level of each root is examined: leftover artifacts are
  /// keyed by bundle identifier or app name at the root level, and matching
  /// deeper would trade precision for noise.
  public func scan(for identity: AppIdentity, computeSizes: Bool = true) -> [LeftoverItem] {
    let fm = FileManager.default
    var items: [LeftoverItem] = []
    for root in roots {
      guard
        let entries = try? fm.contentsOfDirectory(
          at: root.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
      else {
        continue
      }
      for entry in entries {
        guard let confidence = Matcher.match(entryName: entry.lastPathComponent, identity: identity)
        else { continue }
        let size = computeSizes ? FileSize.allocatedSize(at: entry) : nil
        items.append(
          LeftoverItem(url: entry, kind: root.kind, confidence: confidence, sizeBytes: size))
      }
    }
    return items.sorted { lhs, rhs in
      if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
      return lhs.url.path < rhs.url.path
    }
  }
}
