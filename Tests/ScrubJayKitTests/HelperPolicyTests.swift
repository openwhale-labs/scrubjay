import Foundation
import Testing

@testable import ScrubJayKit

/// The helper's allow-list is the boundary that keeps a root daemon from
/// becoming a general-purpose file mover. These tests pin the policy data
/// itself; the helper target applies it (see Helper/main.swift).
@Suite("Helper policy")
struct HelperPolicyTests {
  @Test func allowedRootsMatchTheScannerSystemRoots() {
    let scanned = Set(LeftoverCatalog.systemRoots().map { $0.url.standardizedFileURL.path })
    let allowed = Set(HelperConstants.allowedLibraryRoots)
    // The helper must accept exactly what the scanner can surface — no
    // more (extra privilege) and no less (items the app cannot remove).
    #expect(allowed == scanned)
  }

  @Test func sensitiveLibraryDirectoriesAreNotReachable() {
    for path in [
      "/Library/Keychains", "/Library/Security", "/Library/Extensions",
      "/Library/Frameworks", "/Library/Internet Plug-Ins", "/Library/Input Methods",
      "/Library/StartupItems", "/Library/Managed Preferences"
    ] {
      #expect(!HelperConstants.allowedLibraryRoots.contains(path))
    }
  }

  @Test func allowedRootsAreLibraryDirectoriesNotPrefixes() {
    for root in HelperConstants.allowedLibraryRoots {
      #expect(root.hasPrefix("/Library/"))
      // A trailing slash would turn an exact-parent comparison into a
      // prefix match.
      #expect(!root.hasSuffix("/"))
    }
    #expect(HelperConstants.applicationsRoot == "/Applications")
  }

  @Test func everySystemScanResultHasAnAllowedParent() {
    // A leftover the scanner reports under a system root is exactly one
    // level down, which is what the helper accepts.
    for root in LeftoverCatalog.systemRoots() {
      let child = root.url.appendingPathComponent("com.example.app")
      #expect(LeftoverCatalog.isSystemPath(child))
      #expect(
        HelperConstants.allowedLibraryRoots.contains(
          child.deletingLastPathComponent().standardizedFileURL.path))
    }
  }
}
