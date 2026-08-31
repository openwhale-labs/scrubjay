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

  func writeBundle(at url: URL, bundleID: String) throws {
    let contents = url.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
      <key>CFBundleIdentifier</key><string>\(bundleID)</string>
      <key>CFBundleName</key><string>Fixture</string>
      </dict></plist>
      """
    try plist.data(using: .utf8)!.write(to: contents.appendingPathComponent("Info.plist"))
  }

  @Test func embeddedBundlesClaimTheirFiles() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // An Electron-style app: the outer bundle plus a separately identified
    // main bundle under MacOS and a login item helper.
    let outer = home.appendingPathComponent("Apps/Whale.app")
    try writeBundle(at: outer, bundleID: "com.whale.whale")
    try writeBundle(
      at: outer.appendingPathComponent("Contents/MacOS/Whale Desktop.app"),
      bundleID: "com.electron.whaledesktop")
    try writeBundle(
      at: outer.appendingPathComponent("Contents/Library/LoginItems/WhaleHelper.app"),
      bundleID: "com.whale.helper")
    for cacheDir in ["com.electron.whaledesktop", "com.whale.helper"] {
      try FileManager.default.createDirectory(
        at: home.appendingPathComponent("Library/Caches/\(cacheDir)"),
        withIntermediateDirectories: true)
    }

    let apps = AppInventory.discoverApps(in: [home.appendingPathComponent("Apps")])
    let embedded = AppInventory.embeddedIdentities(of: apps)
    #expect(
      Set(embedded.map(\.bundleID)) == ["com.electron.whaledesktop", "com.whale.helper"])

    let items = scanner(home).scan(
      installed: apps.map(\.identity) + embedded, computeSizes: false)
    #expect(!items.contains { $0.url.lastPathComponent.hasPrefix("com.electron") })
    #expect(!items.contains { $0.url.lastPathComponent == "com.whale.helper" })
  }

  @Test func liveLaunchAgentsAreNotOrphans() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let program = home.appendingPathComponent("updater-binary")
    try Data().write(to: program)
    let agents = home.appendingPathComponent("Library/LaunchAgents")
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    func agent(_ name: String, program: String) throws {
      let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(name)</string>
        <key>ProgramArguments</key><array><string>\(program)</string></array>
        </dict></plist>
        """
      try plist.data(using: .utf8)!.write(to: agents.appendingPathComponent("\(name).plist"))
    }
    try agent("com.live.updater", program: program.path)
    try agent("com.dead.updater", program: "/nowhere/updater-binary")

    let names = Set(
      scanner(home).scan(installed: [chrome], computeSizes: false)
        .map(\.url.lastPathComponent))
    #expect(!names.contains("com.live.updater.plist"))
    #expect(names.contains("com.dead.updater.plist"))
  }

  @Test func liveAgentBundlesJoinTheClaimSet() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }
    // An updater installed under Application Support, wired in through a
    // launch agent — its caches must be claimed, not listed as orphans.
    let updater = home.appendingPathComponent("Library/Application Support/Fixture/Updater.app")
    try writeBundle(at: updater, bundleID: "com.fixture.updater")
    let binary = updater.appendingPathComponent("Contents/MacOS/Updater")
    try FileManager.default.createDirectory(
      at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: binary)
    let agents = home.appendingPathComponent("Library/LaunchAgents")
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
      <key>Label</key><string>com.fixture.updater.wake</string>
      <key>ProgramArguments</key><array><string>\(binary.path)</string></array>
      </dict></plist>
      """
    try plist.data(using: .utf8)!.write(
      to: agents.appendingPathComponent("com.fixture.updater.wake.plist"))
    try FileManager.default.createDirectory(
      at: home.appendingPathComponent("Library/Caches/com.fixture.updater"),
      withIntermediateDirectories: true)

    let agentIdentities = AppInventory.launchAgentIdentities(in: [agents])
    #expect(agentIdentities.map(\.bundleID) == ["com.fixture.updater"])

    let items = scanner(home).scan(
      installed: [chrome] + agentIdentities, computeSizes: false)
    #expect(!items.contains { $0.url.lastPathComponent == "com.fixture.updater" })
  }
}
