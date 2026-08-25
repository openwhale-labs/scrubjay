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

  @Test func recognisesPermissionErrors() {
    let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
    // The shape trashItem actually throws: a Cocoa write-permission error
    // wrapping the POSIX refusal.
    let wrapped = NSError(
      domain: NSCocoaErrorDomain,
      code: CocoaError.fileWriteNoPermission.rawValue,
      userInfo: [NSUnderlyingErrorKey: posix])
    #expect(Trasher.isPermissionDenied(wrapped))
    #expect(Trasher.isPermissionDenied(posix))
    #expect(
      Trasher.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
    #expect(
      !Trasher.isPermissionDenied(
        NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileNoSuchFile.rawValue)))
  }
}
