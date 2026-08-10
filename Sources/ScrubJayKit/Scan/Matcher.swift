import Foundation

/// The minimal identity needed to match leftovers to an app.
public struct AppIdentity: Sendable, Hashable {
  public let bundleID: String
  /// Display name, e.g. "Visual Studio Code" (the /Applications file name).
  public let name: String
  /// Other names the app is known by, e.g. its CFBundleName "Code" — leftover
  /// directories are frequently keyed by these.
  public let altNames: [String]

  public init(bundleID: String, name: String, altNames: [String] = []) {
    self.bundleID = bundleID
    self.name = name
    self.altNames = altNames
  }

  /// All names that participate in matching.
  public var allNames: [String] { [name] + altNames }
}

/// Pure name-matching logic. No filesystem access — fully unit-testable.
public enum Matcher {
  /// Well-known suffixes that follow a bundle identifier in file names,
  /// e.g. `com.google.Chrome.plist` or `com.google.Chrome.savedState`.
  /// Stored lowercase; matching is case-insensitive.
  private static let knownSuffixes: Set<String> = [
    "plist", "savedstate", "binarycookies", "plist.lockfile", "sfl2", "sfl3", "sfl4",
  ]

  /// Names too generic to mean anything on their own.
  private static let genericNames: Set<String> = [
    "app", "apps", "helper", "agent", "cache", "caches", "log", "logs",
    "support", "library", "data", "temp", "tmp", "update", "updater",
  ]

  /// Release-channel tokens. `com.google.Chrome.beta.plist` is prefixed by
  /// Chrome's bundle ID but belongs to Chrome Beta — a different app. When a
  /// prefix match continues with one of these, the entry is reported at `low`
  /// so it is never selected automatically.
  private static let channelTokens: Set<String> = [
    "beta", "canary", "dev", "nightly", "alpha", "preview", "insiders",
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
      if knownSuffixes.contains(suffix) {
        return .certain
      }
      // A channel token right after the bundle ID usually denotes a sibling
      // app (Chrome Beta, VS Code Insiders). Report, but never preselect.
      if let firstToken = suffix.split(separator: ".").first,
        channelTokens.contains(String(firstToken))
      {
        return .low
      }
      return .high
    }

    // Name matches. Normalization strips separators so that
    // "Google Chrome", "google-chrome" and "GoogleChrome" all compare equal.
    let normalizedEntry = normalize(entryName)
    for name in identity.allNames {
      let normalizedName = normalize(name)
      guard !normalizedName.isEmpty, !genericNames.contains(normalizedName) else {
        continue
      }
      if normalizedEntry == normalizedName {
        // Very short names ("Arc", "IINA") collide too easily to trust.
        return normalizedName.count <= 3 ? .low : .medium
      }
    }

    return nil
  }

  /// Match a child entry inside a vendor directory, e.g. `Chrome` inside
  /// `Application Support/Google/`. Bundle-ID rules apply unchanged; on top
  /// of them, vendor name + child name may compose the app name
  /// ("Google" + "Chrome" → "Google Chrome").
  public static func matchVendorChild(
    vendorDir: String, entryName: String, identity: AppIdentity
  ) -> Confidence? {
    if let direct = match(entryName: entryName, identity: identity) {
      return direct
    }
    let composed = normalize(vendorDir) + normalize(entryName)
    guard !normalize(entryName).isEmpty else { return nil }
    for name in identity.allNames where composed == normalize(name) {
      return .medium
    }
    return nil
  }

  /// The vendor token of a reverse-DNS bundle ID: `com.google.Chrome` →
  /// `google`. Requires at least vendor + product components.
  public static func vendorToken(bundleID: String) -> String? {
    let parts = bundleID.split(separator: ".")
    guard parts.count >= 3 else { return nil }
    return String(parts[1]).lowercased()
  }

  /// The reverse-DNS stem of a file name, or nil when the name does not look
  /// like a bundle identifier. `com.foo.Bar.plist` → `com.foo.bar`;
  /// `Google Chrome` → nil.
  public static func bundleIDStem(of entryName: String) -> String? {
    var stem = entryName.lowercased()
    var stripped = true
    while stripped {
      stripped = false
      for suffix in knownSuffixes.sorted(by: { $0.count > $1.count })
      where stem.hasSuffix("." + suffix) {
        stem = String(stem.dropLast(suffix.count + 1))
        stripped = true
      }
    }
    let labels = stem.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 3, labels.allSatisfy({ !$0.isEmpty }) else { return nil }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    guard
      labels.allSatisfy({ $0.unicodeScalars.allSatisfy(allowed.contains) })
    else { return nil }
    return stem
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
