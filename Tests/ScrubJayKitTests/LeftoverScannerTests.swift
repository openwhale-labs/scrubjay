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
        "com.google.Chrome.sfl4",
      ])
    #expect(items.count == 8)  // com.google.Chrome appears in two roots

    // The launch agent carries its parsed label; a fixture label is never
    // loaded in the real launchd domain.
    let agentItem = items.first { $0.url.lastPathComponent == "com.google.Chrome.agent.plist" }
    #expect(agentItem?.launchAgent == LaunchAgentInfo(
      label: "com.google.Chrome.agent", isLoaded: false))
    #expect(items.allSatisfy { $0.confidence >= .medium })
    // Sorted by confidence, certain first.
    #expect(items.first?.confidence == .certain)
    #expect(items.last?.confidence == .medium)
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
}
