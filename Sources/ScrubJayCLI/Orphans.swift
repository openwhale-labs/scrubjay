import ArgumentParser
import Foundation
import ScrubJayKit

struct Orphans: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Find leftovers of apps that are no longer installed.",
    discussion: """
      Lists bundle-identifier-keyed files no installed app claims. Read-only: \
      review the list, then remove what you recognize in the app, or by hand.
      """
  )

  @Flag(name: .long, help: "Skip size computation for a faster scan.")
  var noSizes = false

  func run() throws {
    let installed =
      AppInventory.discoverApps().map(\.identity) + AppInventory.auxiliaryIdentities()
    let items = OrphanScanner.forCurrentUser().scan(installed: installed, computeSizes: !noSizes)
    guard !items.isEmpty else {
      print("No orphaned leftovers found.")
      return
    }

    var total: Int64 = 0
    for (confidence, title) in [
      (Confidence.medium, "No related app installed"),
      (Confidence.low, "Vendor apps still installed — often shared tooling"),
    ] {
      let group = items.filter { $0.confidence == confidence }
      guard !group.isEmpty else { continue }
      print("[\(title)]")
      for item in group {
        let size = item.sizeBytes.map { "  (\(FileSize.format($0)))" } ?? ""
        print("  \(item.url.path)\(size)")
        total += item.sizeBytes ?? 0
      }
      print("")
    }
    let suffix = noSizes ? "" : ", \(FileSize.format(total))"
    print("\(items.count) items\(suffix)")
  }
}
