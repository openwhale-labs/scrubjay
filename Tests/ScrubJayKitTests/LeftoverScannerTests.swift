import Foundation
import Testing

@testable import ScrubJayKit

@Suite("LeftoverScanner")
struct LeftoverScannerTests {
  /// Build a fake home directory with a Library layout and some fixtures.
  func makeFixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("scrubjay-tests-\(UUID().uuidString)", isDirectory: true)
    let fm = FileManager.default

    func create(_ path: String, file: Bool = false, contents: String = "x") throws {
      let url = home.appendingPathComponent(path)
      if file {
        try fm.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)!.write(to: url)
      } else {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
      }
    }

    // Belongs to Chrome.
    try create("Library/Application Support/Google Chrome")
    try create("Library/Caches/com.google.Chrome")
    try create("Library/Preferences/com.google.Chrome.plist", file: true)
    try create("Library/Saved Application State/com.google.Chrome.savedState")
    try create("Library/HTTPStorages/com.google.Chrome")
    // Vendor-nested: Application Support/Google/Chrome plus siblings that
    // must not be swept along.
    try create("Library/Application Support/Google/Chrome")
    try create("Library/Application Support/Google/Chrome Beta")
    try create("Library/Application Support/Google/GoogleUpdater")
    try create("Library/Application Support/Google/RLZ")
    // Sibling channel app.
    try create("Library/Preferences/com.google.Chrome.beta.plist", file: true)
    // Launch agent with a real plist payload.
    try create(
      "Library/LaunchAgents/com.google.Chrome.agent.plist", file: true,
      contents: """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>com.google.Chrome.agent</string>
        </dict></plist>
        """)
    // Recent-documents shared file list.
    try create(
      "Library/Application Support/com.apple.sharedfilelist/"
        + "com.apple.LSSharedFileList.ApplicationRecentDocuments/com.google.Chrome.sfl4",
      file: true)
    // Group container with a team-ID prefix.
    try create("Library/Group Containers/5A4RE8SF68.com.google.Chrome")
    try create("Library/Group Containers/UBF8T346G9.com.microsoft.teams")
    // Unrelated.
    try create("Library/Caches/org.mozilla.firefox")
    try create("Library/Preferences/com.google.Chromecast.plist", file: true)
    try create("Library/Application Support/Slack")
    return home
  }

  let chrome = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")
  let chromeBeta = AppIdentity(bundleID: "com.google.Chrome.beta", name: "Google Chrome Beta")

  @Test func findsChromeLeftoversAndNothingElse() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let scanner = LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home))
    let items = scanner.scan(for: chrome, amongInstalled: [chrome, chromeBeta], computeSizes: false)

    let paths = items.map { $0.url.lastPathComponent }
    #expect(
      Set(paths) == [
        "Google Chrome", "com.google.Chrome", "com.google.Chrome.plist",
        "com.google.Chrome.savedState", "Chrome", "com.google.Chrome.agent.plist",
        "com.google.Chrome.sfl4", "5A4RE8SF68.com.google.Chrome"
      ])
    #expect(items.count == 9)  // com.google.Chrome appears in two roots

    // Group containers can be shared within a vendor: always low.
    let belowMedium = items.filter { $0.confidence < .medium }
    #expect(belowMedium.map { $0.url.lastPathComponent } == ["5A4RE8SF68.com.google.Chrome"])

    // The launch agent carries its parsed label; a fixture label is never
    // loaded in the real launchd domain.
    let agentItem = items.first { $0.url.lastPathComponent == "com.google.Chrome.agent.plist" }
    #expect(agentItem?.launchAgent == LaunchAgentInfo(
      label: "com.google.Chrome.agent", isLoaded: false))
    #expect(agentItem?.launchAgent?.belongsTo(bundleID: "com.google.Chrome") == true)
    #expect(agentItem?.launchAgent?.belongsTo(bundleID: "com.google.Chromecast") == false)
    // Sorted by confidence, certain first; the shared group container ranks last.
    #expect(items.first?.confidence == .certain)
    #expect(items.last?.confidence == .low)
  }

  @Test func ambiguousNameMatchIsSkipped() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    // Two installed apps both known as "Google Chrome" by name: the
    // name-keyed directory cannot be attributed and is left alone.
    let impostor = AppIdentity(bundleID: "com.example.Impostor", name: "Google Chrome")
    let scanner = LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home))
    let items = scanner.scan(
      for: chrome, amongInstalled: [chrome, chromeBeta, impostor], computeSizes: false)
    #expect(!items.contains { $0.url.lastPathComponent == "Google Chrome" })
    // Bundle-ID matches are unaffected.
    #expect(items.contains { $0.url.lastPathComponent == "com.google.Chrome.plist" })
  }

  @Test func vendorNestedChildIsFoundButSiblingsAreNot() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let scanner = LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home))
    let items = scanner.scan(for: chrome, amongInstalled: [chrome, chromeBeta], computeSizes: false)

    let nested = items.filter { $0.url.path.contains("/Google/") }
    #expect(nested.map { $0.url.lastPathComponent } == ["Chrome"])
    // The vendor directory itself is never a result.
    #expect(!items.contains { $0.url.lastPathComponent == "Google" })
  }

  @Test func rivalChannelAppClaimsItsFiles() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let scanner = LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home))

    // With Chrome Beta installed, its plist is not attributed to Chrome.
    let withBeta = scanner.scan(
      for: chrome, amongInstalled: [chrome, chromeBeta], computeSizes: false)
    #expect(!withBeta.contains { $0.url.lastPathComponent == "com.google.Chrome.beta.plist" })

    // Without Chrome Beta installed, the file is reported — at low, never
    // preselected.
    let withoutBeta = scanner.scan(for: chrome, amongInstalled: [chrome], computeSizes: false)
    let betaPlist = withoutBeta.first { $0.url.lastPathComponent == "com.google.Chrome.beta.plist" }
    #expect(betaPlist?.confidence == .low)
  }

  @Test func scanningBetaFindsItsOwnFiles() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let scanner = LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home))
    let items = scanner.scan(
      for: chromeBeta, amongInstalled: [chrome, chromeBeta], computeSizes: false)

    let paths = Set(items.map { $0.url.lastPathComponent })
    #expect(paths.contains("com.google.Chrome.beta.plist"))
    #expect(paths.contains("Chrome Beta"))
    // Chrome's own files are never attributed to Beta.
    #expect(!paths.contains("com.google.Chrome.plist"))
    #expect(!paths.contains("Chrome"))
    #expect(!paths.contains("Google Chrome"))
  }

  @Test func missingRootsAreSkipped() {
    let scanner = LeftoverScanner(
      roots: LeftoverCatalog.userRoots(home: URL(fileURLWithPath: "/nonexistent-home")))
    let identity = AppIdentity(bundleID: "com.example.App", name: "Example")
    #expect(scanner.scan(for: identity).isEmpty)
  }

  @Test func computesSizes() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let scanner = LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home))
    let identity = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")
    let items = scanner.scan(for: identity, computeSizes: true)
    let plist = items.first { $0.url.lastPathComponent == "com.google.Chrome.plist" }
    #expect((plist?.sizeBytes ?? 0) > 0)
  }

  @Test func footprintReportsUnreadableRootsButNotAbsentRoots() throws {
    let home = try makeFixtureHome()
    let manager = FileManager.default
    let denied = home.appendingPathComponent("Library/Containers")
    try manager.createDirectory(at: denied, withIntermediateDirectories: true)
    defer {
      try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
      try? manager.removeItem(at: home)
    }
    try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
    let bundle = home.appendingPathComponent("Example.app")
    try Data(repeating: 42, count: 8192).write(to: bundle)
    let app = InstalledApp(
      bundleID: chrome.bundleID, name: chrome.name, bundleURL: bundle, version: nil)
    let footprint = AppFootprint.scan(
      app: app, amongInstalled: [chrome, chromeBeta],
      scanner: LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home)))

    #expect(!footprint.items.isEmpty)
    #expect(footprint.totalSize > 0)
    #expect(footprint.isIncomplete)
    #expect(footprint.unreadableURLs.map(\.path) == [denied.path])
  }

  @Test func unreadableVendorDirectoryIsReported() throws {
    let home = try makeFixtureHome()
    let manager = FileManager.default
    let denied = home.appendingPathComponent("Library/Application Support/Google")
    defer {
      try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
      try? manager.removeItem(at: home)
    }
    try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
    var failures: [URL] = []
    let scanner = LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home))
    _ = scanner.scan(for: chrome, computeSizes: false) { failed, _ in failures.append(failed) }
    let resolvedFailures = failures.map { $0.resolvingSymlinksInPath().path }
    #expect(resolvedFailures == [denied.resolvingSymlinksInPath().path])
  }
}
