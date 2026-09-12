import Darwin
import Foundation
import Testing

@testable import ScrubJayKit

@Suite("File size read failures")
struct FileSizeTests {
  @Test func pipesAndSymlinksDoNotReportMissingDiskSizes() throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: home) }
    let pipe = home.appendingPathComponent("pipe")
    #expect(mkfifo(pipe.path, 0o600) == 0)
    try manager.createSymbolicLink(
      at: home.appendingPathComponent("link"), withDestinationURL: pipe)
    var failures: [URL] = []
    let size = FileSize.allocatedSize(at: home) { failed, _ in failures.append(failed) }
    #expect(size == 0)
    #expect(failures.isEmpty)
    #expect(FileSize.allocatedSize(at: pipe) == 0)
  }

  @Test func readableDirectoriesDoNotCountAsReadFailures() throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let nested = home.appendingPathComponent("nested/empty")
    try manager.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: home) }
    try Data(repeating: 42, count: 8192).write(to: home.appendingPathComponent("nested/file"))
    var failures: [URL] = []
    let size = FileSize.allocatedSize(at: home) { failed, _ in failures.append(failed) }
    #expect((size ?? 0) > 0)
    #expect(failures.isEmpty)
  }

  @Test func missingFileIsUnknownInsteadOfZero() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var failures: [URL] = []
    let size = FileSize.allocatedSize(at: url) { failed, _ in failures.append(failed) }
    #expect(size == nil)
    #expect(failures == [url])
  }

  @Test func unreadableDescendantIsReportedAlongsideReadableBytes() throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    let denied = home.appendingPathComponent("denied")
    try manager.createDirectory(at: denied, withIntermediateDirectories: true)
    defer {
      try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
      try? manager.removeItem(at: home)
    }
    try Data(repeating: 42, count: 8192).write(to: home.appendingPathComponent("readable"))
    try Data(repeating: 43, count: 8192).write(to: denied.appendingPathComponent("hidden"))
    try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)

    var failures: [URL] = []
    let size = FileSize.allocatedSize(at: home) { failed, _ in failures.append(failed) }
    #expect((size ?? 0) > 0)
    let failedPaths = failures.map { $0.resolvingSymlinksInPath().path }
    #expect(failedPaths.contains(denied.resolvingSymlinksInPath().path))
  }
}
