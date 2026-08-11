import Foundation

/// Scans search roots for files belonging to an app.
public struct LeftoverScanner: Sendable {
  public let roots: [SearchRoot]

  public init(roots: [SearchRoot]) {
    self.roots = roots
  }

  /// Convenience scanner over the current user's Library plus the readable
  /// system-domain roots.
  public static func forCurrentUser() -> LeftoverScanner {
    LeftoverScanner(
      roots: LeftoverCatalog.userRoots(home: FileManager.default.homeDirectoryForCurrentUser)
        + LeftoverCatalog.systemRoots())
  }

  /// Root kinds where vendors commonly nest per-app data one level down,
  /// e.g. `Application Support/Google/Chrome`.
  private static let vendorNestedKinds: Set<LeftoverKind> = [
    .applicationSupport, .caches, .logs
  ]

  /// Scan all roots for entries matching the app identity.
  ///
  /// - Parameters:
  ///   - identity: the app being uninstalled.
  ///   - others: identities of all other installed apps. Any entry that a
  ///     longer bundle identifier claims (Chrome Beta over Chrome) is
  ///     attributed to that app and excluded here. Deliberately biased
  ///     toward missing a file over deleting a wrong one.
  ///   - computeSizes: compute allocated sizes for results.
  public func scan(
    for identity: AppIdentity,
    amongInstalled others: [AppIdentity] = [],
    computeSizes: Bool = true
  ) -> [LeftoverItem] {
    let fm = FileManager.default
    let rivals = others.filter { $0.bundleID.lowercased() != identity.bundleID.lowercased() }
    var items: [LeftoverItem] = []

    func append(_ url: URL, _ kind: LeftoverKind, _ confidence: Confidence) {
      let size = computeSizes ? FileSize.allocatedSize(at: url) : nil
      let agent = kind == .launchAgents ? LaunchAgents.info(forPlistAt: url) : nil
      items.append(
        LeftoverItem(url: url, kind: kind, confidence: confidence, sizeBytes: size,
          launchAgent: agent))
    }

    for root in roots {
      guard
        let entries = try? fm.contentsOfDirectory(
          at: root.url, includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles])
      else {
        continue
      }
      for entry in entries {
        let name = entry.lastPathComponent
        // Group Containers use team-ID-prefixed names and can be shared
        // between a vendor's apps — dedicated matching, always `low`.
        if root.kind == .groupContainers {
          if let confidence = Matcher.matchGroupContainer(entryName: name, identity: identity),
            !claimedByRival(name, target: identity, rivals: rivals) {
            append(entry, root.kind, confidence)
          }
          continue
        }
        if let confidence = Matcher.match(entryName: name, identity: identity) {
          // A name-based match that also name-matches another installed app
          // is ambiguous — leave it alone.
          let ambiguous =
            Matcher.nameMatches(entryName: name, identity: identity)
            && rivals.contains { Matcher.nameMatches(entryName: name, identity: $0) }
          if !ambiguous, !claimedByRival(name, target: identity, rivals: rivals) {
            append(entry, root.kind, confidence)
          }
          continue
        }
        // Vendor directory descent: only into a directory named after the
        // app's own vendor, only one level, and never the vendor dir itself.
        if Self.vendorNestedKinds.contains(root.kind),
          let vendor = Matcher.vendorToken(bundleID: identity.bundleID),
          Matcher.normalize(name) == vendor,
          (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
          let children = try? fm.contentsOfDirectory(
            at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
          for child in children {
            let childName = child.lastPathComponent
            guard
              let confidence = Matcher.matchVendorChild(
                vendorDir: name, entryName: childName, identity: identity),
              !claimedByRival(childName, target: identity, rivals: rivals),
              !claimedByRivalName(vendorDir: name, childName: childName, rivals: rivals)
            else { continue }
            append(child, root.kind, confidence)
          }
        }
      }
    }
    return items.sorted { lhs, rhs in
      if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
      return lhs.url.path < rhs.url.path
    }
  }

  /// True when another installed app's (longer) bundle identifier claims the
  /// entry, e.g. `com.google.Chrome.beta.plist` while Chrome Beta is
  /// installed.
  private func claimedByRival(
    _ entryName: String, target: AppIdentity, rivals: [AppIdentity]
  ) -> Bool {
    let entry = entryName.lowercased()
    let targetLength = target.bundleID.count
    for rival in rivals {
      let rivalID = rival.bundleID.lowercased()
      guard rivalID.count > targetLength else { continue }
      if entry == rivalID || entry.hasPrefix(rivalID + ".") {
        return true
      }
    }
    return false
  }

  /// True when a vendor-directory child composes another installed app's
  /// name, e.g. `Google` + `Chrome Beta` while Chrome Beta is installed.
  private func claimedByRivalName(
    vendorDir: String, childName: String, rivals: [AppIdentity]
  ) -> Bool {
    let composed = Matcher.normalize(vendorDir) + Matcher.normalize(childName)
    let direct = Matcher.normalize(childName)
    return rivals.contains { rival in
      rival.allNames.contains { name in
        let rivalName = Matcher.normalize(name)
        return !rivalName.isEmpty && (composed == rivalName || direct == rivalName)
      }
    }
  }
}
