import Foundation
import Testing

@testable import ScrubJayKit

@Suite("DevCaches")
struct DevCachesTests {
  @Test func catalogIDsAreUnique() {
    let ids = DevCaches.catalog(home: URL(fileURLWithPath: "/tmp")).map(\.id)
    #expect(Set(ids).count == ids.count)
  }

  @Test func presentReturnsOnlyExistingDirectories() throws {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("scrubjay-dev-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(
      at: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
      withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: home.appendingPathComponent(".npm/_cacache"), withIntermediateDirectories: true)

    let present = DevCaches.present(home: home, computeSizes: false)
    #expect(present.map(\.id).sorted() == ["npm", "xcode-deriveddata"])
  }

  @Test func emptyHomeYieldsNothing() {
    let present = DevCaches.present(
      home: URL(fileURLWithPath: "/nonexistent-home"), computeSizes: false)
    #expect(present.isEmpty)
  }
}
