import Foundation
import Testing

@testable import ScrubJayKit

@Suite("BackgroundItems")
struct BackgroundItemsTests {
  /// Shaped exactly like `sfltool dumpbtm` output, including the parent app
  /// rows children hang off, a grouping "developer" row, and the
  /// percent-encoded relative URLs the database actually stores.
  let dump = """
     #1:
                     UUID: 11111111-1111-1111-1111-111111111111
                     Name: Example
           Developer Name: Example Inc
                     Type: developer (0x20)
              Disposition: [disabled, allowed, not notified] (0x2)
               Identifier: 1.example

     #2:
                     UUID: 22222222-2222-2222-2222-222222222222
                     Name: Gone
           Developer Name: Gone Ltd
                     Type: app (0x2)
              Disposition: [disabled, allowed, not notified] (0x2)
               Identifier: 2.com.gone.app
                      URL: file:///Users/tester/.Trash/Gone.app/
        Bundle Identifier: com.gone.app

     #3:
                     UUID: 33333333-3333-3333-3333-333333333333
                     Name: Gone Launcher
           Developer Name: Gone Ltd
                     Type: login item (0x4)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 4.com.gone.launcher
                      URL: Contents/Library/LoginItems/Gone%20Launcher.app
        Parent Identifier: 2.com.gone.app

     #4:
                     UUID: 44444444-4444-4444-4444-444444444444
                     Name: Present
           Developer Name: (null)
                     Type: app (0x2)
              Disposition: [enabled, allowed, notified] (0xb)
               Identifier: 2.com.present.app
                      URL: file:///PRESENT_PATH/
        Bundle Identifier: com.present.app
    """

  func fixture() throws -> (dump: String, home: URL) {
    // A real directory stands in for the installed app, so "still present"
    // is decided by the filesystem rather than by the test's wishes.
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("scrubjay-btm-\(UUID().uuidString)", isDirectory: true)
    let present = home.appendingPathComponent("Present.app", isDirectory: true)
    try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
    return (dump.replacingOccurrences(of: "/PRESENT_PATH/", with: present.path + "/"), home)
  }

  @Test func parsesItemsAndSkipsDeveloperRows() throws {
    let (text, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let items = BackgroundItems.parse(dump: text)
    #expect(items.map(\.name) == ["Gone", "Gone Launcher", "Present"])
    #expect(!items.contains { $0.kind == "developer" })
  }

  @Test func resolvesRelativeChildAgainstItsParentBundle() throws {
    let (text, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let launcher = BackgroundItems.parse(dump: text).first { $0.name == "Gone Launcher" }
    #expect(
      launcher?.url?.path
        == "/Users/tester/.Trash/Gone.app/Contents/Library/LoginItems/Gone Launcher.app")
    #expect(launcher?.isEnabled == true)
    #expect(launcher?.kind == "login")
  }

  @Test func flagsItemsWhoseAppSitsInTheTrash() throws {
    let (text, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let items = BackgroundItems.parse(dump: text)
    let stale = BackgroundItems.stale(
      in: items, trash: URL(fileURLWithPath: "/Users/tester/.Trash"))
    #expect(stale.map(\.item.name).sorted() == ["Gone", "Gone Launcher"])
    #expect(stale.allSatisfy { $0.reason == .appInTrash })
  }

  @Test func installedAppsAreNotFlagged() throws {
    let (text, home) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let stale = BackgroundItems.stale(
      in: BackgroundItems.parse(dump: text),
      trash: URL(fileURLWithPath: "/Users/tester/.Trash"))
    #expect(!stale.contains { $0.item.name == "Present" })
  }

  @Test func missingAppsAreFlaggedSeparately() throws {
    let text = dump.replacingOccurrences(of: "/PRESENT_PATH/", with: "/nowhere/Present.app/")
    let stale = BackgroundItems.stale(
      in: BackgroundItems.parse(dump: text),
      trash: URL(fileURLWithPath: "/Users/tester/.Trash"))
    let present = stale.first { $0.item.name == "Present" }
    #expect(present?.reason == .appMissing)
  }
}
