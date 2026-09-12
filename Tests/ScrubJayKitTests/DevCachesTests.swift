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

  @Test func measuredEmptyCachesAreHiddenAndPopulatedCachesRemain() throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? manager.removeItem(at: home) }
    let yarn = home.appendingPathComponent("Library/Caches/Yarn/v6/empty")
    let npm = home.appendingPathComponent(".npm/_cacache")
    try manager.createDirectory(at: yarn, withIntermediateDirectories: true)
    try manager.createDirectory(at: npm, withIntermediateDirectories: true)
    try Data().write(to: yarn.appendingPathComponent("zero-byte-file"))
    try Data(repeating: 42, count: 8192).write(to: npm.appendingPathComponent("package"))

    let caches = DevCaches.present(home: home)
    #expect(caches.map(\.id) == ["npm"])
    #expect((caches.first?.sizeBytes ?? 0) > 0)
    #expect(caches.first?.isIncomplete == false)
    try manager.removeItem(at: npm.appendingPathComponent("package"))
    #expect(DevCaches.present(home: home).isEmpty)
  }

  @Test(arguments: [false, true])
  func unreadableCachesAreNotHiddenAsEmpty(withReadableBytes: Bool) throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let npm = home.appendingPathComponent(".npm/_cacache")
    let denied = npm.appendingPathComponent("denied")
    try manager.createDirectory(at: denied, withIntermediateDirectories: true)
    defer {
      try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
      try? manager.removeItem(at: home)
    }
    try Data(repeating: 42, count: 8192).write(to: denied.appendingPathComponent("package"))
    if withReadableBytes {
      try Data(repeating: 43, count: 8192).write(to: npm.appendingPathComponent("readable"))
    }
    try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)

    let caches = DevCaches.present(home: home)
    let cache = try #require(caches.first)
    #expect(caches.map(\.id) == ["npm"])
    #expect(cache.isIncomplete)
    if withReadableBytes {
      #expect((cache.sizeBytes ?? 0) > 0)
      #expect(cache.formattedSize.hasPrefix("≥ "))
    } else {
      #expect(cache.formattedSize == "Size unavailable")
    }
    #expect(DevCacheStatus.formattedTotal(caches) == cache.formattedSize)
  }
}
