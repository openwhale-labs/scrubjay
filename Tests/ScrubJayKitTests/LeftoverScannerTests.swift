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
    // Unrelated.
    try create("Library/Caches/org.mozilla.firefox")
    try create("Library/Preferences/com.google.Chromecast.plist", file: true)
    try create("Library/Application Support/Slack")
    return home
  }

  @Test func findsChromeLeftoversAndNothingElse() throws {
    let home = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: home) }

    let scanner = LeftoverScanner(roots: LeftoverCatalog.userRoots(home: home))
    let identity = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")
    let items = scanner.scan(for: identity, computeSizes: false)

    let paths = Set(items.map { $0.url.lastPathComponent })
    #expect(
      paths == [
        "Google Chrome", "com.google.Chrome", "com.google.Chrome.plist",
        "com.google.Chrome.savedState", "com.google.Chrome",
      ])
    #expect(items.count == 5)
    #expect(items.allSatisfy { $0.confidence >= .medium })
    // Sorted by confidence, certain first.
    #expect(items.first?.confidence == .certain)
    #expect(items.last?.confidence == .medium)
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
