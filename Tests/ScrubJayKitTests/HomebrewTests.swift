import Foundation
import Testing

@testable import ScrubJayKit

@Suite("Homebrew")
struct HomebrewTests {
  /// Build a fake Caskroom mirroring the real layout:
  /// `<root>/<token>/<version>/<App>.app` plus a `.metadata` dir to skip.
  func makeFixtureCaskroom() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("scrubjay-caskroom-\(UUID().uuidString)", isDirectory: true)
    let fm = FileManager.default
    func create(_ path: String) throws {
      try fm.createDirectory(
        at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    try create("jordanbaird-ice/0.11.12/Ice.app")
    try create("jordanbaird-ice/.metadata/0.11.12")
    try create("utm/4.6.4/UTM.app")
    // CLI-only cask: no app artifact, must not be reported.
    try create("gcloud-cli/531.0.0")
    return root
  }

  @Test func findsGUICasksAndSkipsCLIOnes() throws {
    let root = try makeFixtureCaskroom()
    defer { try? FileManager.default.removeItem(at: root) }

    let casks = Homebrew.installedCasks(roots: [root])
    #expect(
      casks == [
        CaskInstall(token: "jordanbaird-ice", appNames: ["Ice.app"]),
        CaskInstall(token: "utm", appNames: ["UTM.app"])
      ])
  }

  @Test func mapsAppNameToToken() throws {
    let root = try makeFixtureCaskroom()
    defer { try? FileManager.default.removeItem(at: root) }

    let casks = Homebrew.installedCasks(roots: [root])
    #expect(Homebrew.caskToken(forAppNamed: "Ice.app", in: casks) == "jordanbaird-ice")
    #expect(Homebrew.caskToken(forAppNamed: "Safari.app", in: casks) == nil)
  }

  @Test func missingRootsYieldNothing() {
    let casks = Homebrew.installedCasks(roots: [URL(fileURLWithPath: "/nonexistent-caskroom")])
    #expect(casks.isEmpty)
  }
}
