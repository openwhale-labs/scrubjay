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

  @Test func auxiliaryBundlesClaimTheirFiles() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // An input method lives outside /Applications but is alive.
    try FileManager.default.createDirectory(
      at: home.appendingPathComponent("Library/Caches/com.doubao.ime"),
      withIntermediateDirectories: true)
    let imeDir = home.appendingPathComponent("Input Methods/FakeIme.app/Contents")
    try FileManager.default.createDirectory(at: imeDir, withIntermediateDirectories: true)
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
      <key>CFBundleIdentifier</key><string>com.doubao.ime</string>
      <key>CFBundleName</key><string>FakeIme</string>
      </dict></plist>
      """
    try plist.data(using: .utf8)!.write(to: imeDir.appendingPathComponent("Info.plist"))

    let aux = AppInventory.auxiliaryIdentities(
      in: [home.appendingPathComponent("Input Methods")])
    #expect(aux.map(\.bundleID) == ["com.doubao.ime"])

    let items = scanner(home).scan(installed: [chrome] + aux, computeSizes: false)
    #expect(!items.contains { $0.url.lastPathComponent == "com.doubao.ime" })
  }

  @Test func frameworkServicesRankAsSharedTooling() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(
      at: home.appendingPathComponent("Library/Caches/org.sparkle-project.DownloaderService"),
      withIntermediateDirectories: true)

    let items = scanner(home).scan(installed: [chrome], computeSizes: false)
    let sparkle = items.first {
      $0.url.lastPathComponent == "org.sparkle-project.DownloaderService"
    }
    #expect(sparkle?.confidence == .low)
  }

  @Test func bundleIDStemParsing() {
    #expect(Matcher.bundleIDStem(of: "com.foo.Bar.plist") == "com.foo.bar")
    #expect(Matcher.bundleIDStem(of: "com.foo.Bar.savedState") == "com.foo.bar")
    #expect(Matcher.bundleIDStem(of: "com.foo.Bar") == "com.foo.bar")
    #expect(Matcher.bundleIDStem(of: "Google Chrome") == nil)
    #expect(Matcher.bundleIDStem(of: "com.foo") == nil)
    #expect(Matcher.bundleIDStem(of: "Adobe") == nil)
  }

  @Test func unwrapsTeamIDAndGroupLabels() {
    #expect(Matcher.unwrapContainerName("group.com.apple.notes") == "com.apple.notes")
    #expect(
      Matcher.unwrapContainerName("243lu875e5.groups.com.apple.podcasts") == "com.apple.podcasts")
    #expect(
      Matcher.unwrapContainerName("vh7g2mrf27.com.prect.navicatpremium.schedulegroup")
        == "com.prect.navicatpremium.schedulegroup")
    #expect(Matcher.unwrapContainerName("com.google.chrome") == "com.google.chrome")
    #expect(
      Matcher.unwrapContainerName("systemgroup.com.apple.icloud.searchpartyd")
        == "com.apple.icloud.searchpartyd")
  }

  @Test func wrappedAppleEntriesAreNeverReported() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    for path in [
      "Library/Caches/group.com.apple.notes",
      "Library/Caches/243LU875E5.groups.com.apple.podcasts",
    ] {
      try FileManager.default.createDirectory(
        at: home.appendingPathComponent(path), withIntermediateDirectories: true)
    }

    let items = scanner(home).scan(installed: [chrome], computeSizes: false)
    #expect(!items.contains { $0.url.lastPathComponent.lowercased().contains("apple") })
  }

  @Test func applicationScriptsRootIsExcluded() {
    let roots = OrphanScanner.forCurrentUser().roots
    #expect(!roots.contains { $0.kind == .applicationScripts })
    #expect(!roots.contains { $0.kind == .groupContainers })
  }
}
