import Foundation

/// The minimal identity needed to match leftovers to an app.
public struct AppIdentity: Sendable, Hashable {
  public let bundleID: String
  public let name: String

  public init(bundleID: String, name: String) {
    self.bundleID = bundleID
    self.name = name
  }
}

/// Pure name-matching logic. No filesystem access — fully unit-testable.
public enum Matcher {
  /// Well-known suffixes that follow a bundle identifier in file names,
  /// e.g. `com.google.Chrome.plist` or `com.google.Chrome.savedState`.
  /// Stored lowercase; matching is case-insensitive.
  private static let knownSuffixes: Set<String> = [
    "plist", "savedstate", "binarycookies", "plist.lockfile", "sfl2", "sfl3",
  ]

  /// Names too generic to mean anything on their own.
  private static let genericNames: Set<String> = [
    "app", "apps", "helper", "agent", "cache", "caches", "log", "logs",
    "support", "library", "data", "temp", "tmp", "update", "updater",
  ]

  /// Decide whether a directory entry belongs to the app.
  ///
  /// - Parameter entryName: the last path component of a candidate file or
  ///   directory, e.g. `com.google.Chrome.plist` or `Google Chrome`.
  /// - Returns: a confidence level, or `nil` when the entry does not match.
  public static func match(entryName: String, identity: AppIdentity) -> Confidence? {
    let entry = entryName.lowercased()
    let bundleID = identity.bundleID.lowercased()

    // Bundle-identifier matches.
    if entry == bundleID {
      return .certain
    }
    if entry.hasPrefix(bundleID + ".") {
      let suffix = String(entry.dropFirst(bundleID.count + 1))
      return knownSuffixes.contains(suffix) ? .certain : .high
    }

    // Name matches. Normalization strips separators so that
    // "Google Chrome", "google-chrome" and "GoogleChrome" all compare equal.
    let normalizedEntry = normalize(entryName)
    let normalizedName = normalize(identity.name)
    guard !normalizedName.isEmpty, !genericNames.contains(normalizedName) else {
      return nil
    }
    if normalizedEntry == normalizedName {
      // Very short names ("Arc", "IINA") collide too easily to trust.
      return normalizedName.count <= 3 ? .low : .medium
    }

    return nil
  }

  static func normalize(_ name: String) -> String {
    // Strip a trailing file extension only when the base still looks like a
    // name (avoids eating "2.0" style version suffixes in directory names).
    var base = name
    let lowered = name.lowercased()
    for ext in [".plist", ".app"] where lowered.hasSuffix(ext) {
      base = String(base.dropLast(ext.count))
    }
    return base.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" && $0 != "." }
  }
}
