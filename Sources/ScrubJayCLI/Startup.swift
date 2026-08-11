import ArgumentParser
import Foundation
import ScrubJayKit

struct Startup: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Find login items and background tasks left by apps that are gone.",
    discussion: """
      Reads macOS's background task management database — the list behind \
      System Settings › General › Login Items & Extensions. Apps dragged to \
      the Trash leave their entries registered and switched on. Reading the \
      database needs root, so run this with sudo.
      """
  )

  @Option(name: .long, help: "Read a saved `sfltool dumpbtm` dump instead of running it.")
  var dump: String?

  func run() throws {
    let text: String
    if let dump {
      text = try String(contentsOfFile: dump, encoding: .utf8)
    } else {
      guard let output = BackgroundItems.readDatabase() else {
        throw ValidationError(
          "Could not read the background item database. Run this with sudo.")
      }
      text = output
    }

    let items = BackgroundItems.parse(dump: text)
    let stale = BackgroundItems.stale(in: items)
    print("\(items.count) background items registered.\n")

    guard !stale.isEmpty else {
      print("None of them belong to a removed app.")
      return
    }
    print("Left behind by apps that are gone:")
    for entry in stale {
      let state = entry.item.isEnabled ? "on " : "off"
      let why = entry.reason == .appInTrash ? "app is in the Trash" : "app is gone"
      print("  [\(state)] \(entry.item.name)  (\(entry.item.kind)) — \(why)")
      if let path = entry.item.url?.path {
        print("        \(path)")
      }
    }
    print(
      """

      \(stale.count) items. These entries outlive the app and even an emptied \
      Trash, and macOS offers no way to remove them one by one. To reset every \
      login item on this Mac at once: sudo sfltool resetbtm (you will \
      re-approve the apps you keep).
      """)
  }
}
