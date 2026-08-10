import ArgumentParser
import Foundation
import ScrubJayKit

struct Apps: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List installed applications."
  )

  @Flag(name: .long, help: "Include Apple's own applications.")
  var includeApple = false

  func run() throws {
    let apps = AppInventory.discoverApps().filter { includeApple || !$0.isAppleApp }
    let nameWidth = apps.map(\.name.count).max() ?? 0
    for app in apps {
      let name = app.name.padding(toLength: nameWidth + 2, withPad: " ", startingAt: 0)
      let version = app.version.map { "  \($0)" } ?? ""
      print("\(name)\(app.bundleID)\(version)")
    }
    FileHandle.standardError.write(Data("\n\(apps.count) apps\n".utf8))
  }
}
