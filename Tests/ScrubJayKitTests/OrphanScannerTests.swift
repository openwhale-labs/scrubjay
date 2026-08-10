import Foundation
import Testing

@testable import ScrubJayKit

@Suite("OrphanScanner")
struct OrphanScannerTests {
  let chrome = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")

  func makeFixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("scrubjay-orphans-\(UUID().uuidString)", isDirectory: true)
    let fm = FileManager.default
    func create(_ path: String) throws {
      try fm.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    try create("Library/Caches/com.google.Chrome")  // claimed by installed app
    try create("Library/Caches/com.deleted.OldApp")  // orphan, vendor gone
    try create("Library/Caches/com.google.Keep")  // orphan, vendor present
    try create("Library/Caches/com.apple.dt.Xcode")  // Apple — never reported
    try create("Library/Caches/SomeRandomFolder")  // not bundle-ID-keyed
    // Wrapped name embedding an installed app's bundle ID — still owned.
    try create("Library/Caches/bugsnag-shared-com.google.Chrome")
    try create("Library/Group Containers/ABCDE12345.com.gone.app")  // excluded root
    return home
  }

  func scanner(_ home: URL) -> OrphanScanner {
    OrphanScanner(
      roots: LeftoverCatalog.userRoots(home: home).filter { $0.kind != .groupContainers })
  }

  @Test func findsOnlyUnclaimedBundleIDEntries() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let items = scanner(home).scan(installed: [chrome], computeSizes: false)
    let names = Set(items.map(\.url.lastPathComponent))
    #expect(names == ["com.deleted.OldApp", "com.google.Keep"])
  }

  @Test func vendorPresenceLowersConfidence() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let items = scanner(home).scan(installed: [chrome], computeSizes: false)
    let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.url.lastPathComponent, $0) })
    #expect(byName["com.deleted.OldApp"]?.confidence == .medium)
    #expect(byName["com.google.Keep"]?.confidence == .low)
  }

  @Test func bundleIDStemParsing() {
    #expect(Matcher.bundleIDStem(of: "com.foo.Bar.plist") == "com.foo.bar")
    #expect(Matcher.bundleIDStem(of: "com.foo.Bar.savedState") == "com.foo.bar")
    #expect(Matcher.bundleIDStem(of: "com.foo.Bar") == "com.foo.bar")
    #expect(Matcher.bundleIDStem(of: "Google Chrome") == nil)
    #expect(Matcher.bundleIDStem(of: "com.foo") == nil)
    #expect(Matcher.bundleIDStem(of: "Adobe") == nil)
  }
}
