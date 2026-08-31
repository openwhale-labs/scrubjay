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
                      URL: file://TRASH_PATH/Gone.app/
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

  /// Real directories stand in for the installed app and for a Trash that
  /// still holds a removed one, so "present" and "in the Trash" are decided
  /// by the filesystem rather than by the test's wishes.
  func fixture() throws -> (dump: String, home: URL, trash: URL) {
    let home = FileManager.default.temporaryDirectory
      .appendingPathComponent("scrubjay-btm-\(UUID().uuidString)", isDirectory: true)
    let trash = home.appendingPathComponent("Trash", isDirectory: true)
    for path in [home.appendingPathComponent("Present.app"), trash.appendingPathComponent("Gone.app")] {
      try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    }
    let text = dump
      .replacingOccurrences(of: "/PRESENT_PATH/", with: home.appendingPathComponent("Present.app").path + "/")
      .replacingOccurrences(of: "TRASH_PATH", with: trash.path)
    return (text, home, trash)
  }

  @Test func parsesItemsAndSkipsDeveloperRows() throws {
    let (text, home, trash) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let items = BackgroundItems.parse(dump: text)
    #expect(items.map(\.name) == ["Gone", "Gone Launcher", "Present"])
    #expect(!items.contains { $0.kind == "developer" })
  }

  @Test func resolvesRelativeChildAgainstItsParentBundle() throws {
    let (text, home, trash) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let launcher = BackgroundItems.parse(dump: text).first { $0.name == "Gone Launcher" }
    #expect(
      launcher?.url?.path
        == trash.appendingPathComponent("Gone.app/Contents/Library/LoginItems/Gone Launcher.app").path)
    #expect(launcher?.isEnabled == true)
    #expect(launcher?.kind == "login")
  }

  @Test func flagsItemsWhoseAppSitsInTheTrash() throws {
    let (text, home, trash) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let items = BackgroundItems.parse(dump: text)
    let stale = BackgroundItems.stale(in: items, trash: trash)
    #expect(stale.map(\.item.name).sorted() == ["Gone", "Gone Launcher"])
    // The bundle itself is still in the Trash; its login item is inside it
    // and therefore gone with it.
    #expect(stale.first { $0.item.name == "Gone" }?.reason == .appInTrash)
  }

  @Test func installedAppsAreNotFlagged() throws {
    let (text, home, trash) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let stale = BackgroundItems.stale(in: BackgroundItems.parse(dump: text), trash: trash)
    #expect(!stale.contains { $0.item.name == "Present" })
  }

  @Test func emptiedTrashReadsAsMissingNotAsInTheTrash() throws {
    // The database keeps pointing into the Trash after it is emptied.
    let (text, home, trash) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let emptied = home.appendingPathComponent("EmptyTrash", isDirectory: true)
    try FileManager.default.createDirectory(at: emptied, withIntermediateDirectories: true)
    let dump = text.replacingOccurrences(
      of: "file://\(trash.path)/Gone.app/", with: "file://\(emptied.path)/Gone.app/")

    let stale = BackgroundItems.stale(in: BackgroundItems.parse(dump: dump), trash: emptied)
    let gone = stale.first { $0.item.name == "Gone" }
    #expect(gone?.reason == .appMissing)
  }

  @Test func missingAppsAreFlaggedSeparately() throws {
    let text = dump
      .replacingOccurrences(of: "/PRESENT_PATH/", with: "/nowhere/Present.app/")
      .replacingOccurrences(of: "TRASH_PATH", with: "/nowhere/.Trash")
    let stale = BackgroundItems.stale(
      in: BackgroundItems.parse(dump: text), trash: URL(fileURLWithPath: "/nowhere/.Trash"))
    let present = stale.first { $0.item.name == "Present" }
    #expect(present?.reason == .appMissing)
  }

  @Test func keepsOnlyTheCallersAndTheSystemSections() throws {
    // The real dump covers every account on the machine. Another user's
    // home is unreadable from this process, so items there would all read
    // as missing; only the caller's section and the system ones survive.
    let (text, home, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: home) }

    let sectioned = """
       Records for UID -2 : FFFFEEEE-DDDD-CCCC-BBBB-AAAAFFFFFFFE

       #1:
                       UUID: 55555555-5555-5555-5555-555555555555
                       Name: System Daemon
                       Type: legacy daemon (0x10010)
                Disposition: [enabled, allowed, notified] (0xb)
                 Identifier: 8.com.system.daemon
                        URL: file:///nowhere/com.system.daemon.plist

       Records for UID 501 : D1C6C408-C2D2-4203-BF6D-C9EC083BD9E6

      \(text)

       Records for UID 502 : 628CC7B3-10F8-45A3-BD06-FF641C25DC13

       #1:
                       UUID: 66666666-6666-6666-6666-666666666666
                       Name: Other Users App
                       Type: app (0x2)
                Disposition: [enabled, allowed, notified] (0xb)
                 Identifier: 2.com.other.app
                        URL: file:///Users/someoneelse/Applications/Other.app/
      """

    let items = BackgroundItems.parse(dump: sectioned, uid: 501)
    #expect(items.map(\.name).contains("System Daemon"))
    #expect(items.map(\.name).contains("Present"))
    #expect(!items.map(\.name).contains("Other Users App"))
  }
}
