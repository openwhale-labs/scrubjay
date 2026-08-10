import Foundation
import Testing

@testable import ScrubJayKit

@Suite("Trasher")
struct TrasherTests {
  @Test func refusesProtectedPaths() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    #expect(Trasher.isProtected(home))
    #expect(Trasher.isProtected(home.appendingPathComponent("Library")))
    #expect(Trasher.isProtected(URL(fileURLWithPath: "/")))
    #expect(Trasher.isProtected(URL(fileURLWithPath: "/Applications")))
    #expect(Trasher.isProtected(URL(fileURLWithPath: "/System")))
  }

  @Test func allowsPathsInsideLibrary() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidate = home.appendingPathComponent("Library/Caches/com.example.app")
    #expect(!Trasher.isProtected(candidate))
  }

  @Test func trashThrowsOnProtectedPath() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    #expect(throws: Trasher.TrashError.protectedPath(home.path)) {
      try Trasher.trash(home)
    }
  }
}
