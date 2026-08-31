import Foundation

/// Finds leftovers of apps that are no longer installed.
///
/// Only entries whose names are bundle identifiers qualify: a name-keyed
/// directory cannot be safely attributed to "no app at all". Entries claimed
/// by any installed app, and everything under `com.apple.`, are excluded.
/// Nothing an orphan scan reports is ever preselected.
public struct OrphanScanner: Sendable {
  public let roots: [SearchRoot]

  public init(roots: [SearchRoot]) {
    self.roots = roots
  }

  /// Bundle-ID prefixes of frameworks whose services run embedded inside
  /// installed apps.
  static let frameworkServicePrefixes: [String] = ["org.sparkle-project."]

  /// True when the launch agent plist names a program that exists on disk.
  static func launchAgentProgramExists(_ url: URL) -> Bool {
    guard let program = LaunchAgents.program(forPlistAt: url) else { return false }
    return FileManager.default.fileExists(atPath: program)
  }

  /// Group Containers and Application Scripts are excluded: both are named
  /// with team-ID and `group.` wrappers that cannot be matched to bundle
  /// identifiers with confidence, and their entries are mostly empty
  /// scaffolding the system rebuilds anyway.
  public static func forCurrentUser() -> OrphanScanner {
    let roots = LeftoverCatalog.userRoots(home: FileManager.default.homeDirectoryForCurrentUser)
      .filter { $0.kind != .groupContainers && $0.kind != .applicationScripts }
    return OrphanScanner(roots: roots)
  }

  /// Scan for entries no installed app claims.
  ///
  /// - Returns: items at `medium` when no installed app shares the entry's
  ///   vendor, `low` when vendor siblings are still installed (their shared
  ///   tooling often lives under names like `com.vendor.updater`).
  public func scan(installed: [AppIdentity], computeSizes: Bool = true) -> [LeftoverItem] {
    let fm = FileManager.default
    var items: [LeftoverItem] = []
    for root in roots {
      guard
        let entries = try? fm.contentsOfDirectory(
          at: root.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
      else { continue }
      for entry in entries {
        let name = entry.lastPathComponent
        guard let stem = Matcher.bundleIDStem(of: name) else { continue }
        // Team-ID and `group.` wrappers hide the owning bundle ID; the
        // Apple check must see through them or `group.com.apple.notes`
        // reads as a third-party orphan.
        let unwrapped = Matcher.unwrapContainerName(stem)
        guard !stem.hasPrefix("com.apple."), !unwrapped.hasPrefix("com.apple.") else {
          continue
        }
        guard !installed.contains(where: { Matcher.match(entryName: name, identity: $0) != nil })
        else { continue }
        // Wrapped names like `bugsnag-shared-com.ticktick.task.mac` embed an
        // installed app's bundle ID — that app still owns them.
        guard !installed.contains(where: { stem.contains($0.bundleID.lowercased()) })
        else { continue }
        // A launch agent whose program still exists belongs to living
        // software — updaters often install under Application Support
        // rather than an Applications folder (Google's does), so the plist
        // name alone cannot condemn the agent.
        if root.kind == .launchAgents, Self.launchAgentProgramExists(entry) {
          continue
        }

        let vendorPrefix = unwrapped.split(separator: ".").prefix(2).joined(separator: ".") + "."
        let vendorStillPresent = installed.contains {
          $0.bundleID.lowercased().hasPrefix(vendorPrefix)
        }
        // Framework services (Sparkle's updater XPC, …) ship embedded in
        // many installed apps; their files rank with shared tooling.
        let isFrameworkService = Self.frameworkServicePrefixes.contains {
          stem.hasPrefix($0)
        }
        let size = computeSizes ? FileSize.allocatedSize(at: entry) : nil
        items.append(
          LeftoverItem(
            url: entry, kind: root.kind,
            confidence: (vendorStillPresent || isFrameworkService) ? .low : .medium,
            sizeBytes: size))
      }
    }
    return items.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
  }
}
