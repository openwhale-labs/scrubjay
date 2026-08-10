import ArgumentParser
import Foundation
import ScrubJayKit

struct Scan: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Find files an app would leave behind."
  )

  @Argument(help: "App name or bundle identifier (fuzzy).")
  var query: String

  @Option(name: .long, help: "Hide results below this confidence: low|medium|high|certain.")
  var minConfidence: Confidence = .low

  @Flag(name: .long, help: "Skip size computation for a faster scan.")
  var noSizes = false

  func run() throws {
    let apps = AppInventory.discoverApps()
    let app = try resolveApp(query: query, among: apps)
    print("\(app.name) (\(app.bundleID)) — \(app.bundleURL.path)\n")

    let scanner = LeftoverScanner.forCurrentUser()
    let others = apps.map(\.identity)
    let items = scanner.scan(for: app.identity, amongInstalled: others, computeSizes: !noSizes)
      .filter { $0.confidence >= minConfidence }

    guard !items.isEmpty else {
      print("No leftover files found.")
      return
    }

    var total: Int64 = 0
    for confidence in Confidence.allCases.reversed() {
      let group = items.filter { $0.confidence == confidence }
      guard !group.isEmpty else { continue }
      print("[\(confidence.label)]")
      for item in group {
        let size = item.sizeBytes.map { "  (\(FileSize.format($0)))" } ?? ""
        let agent = item.launchAgent.map {
          "  [agent \($0.label)\($0.isLoaded ? ", loaded" : "")]"
        } ?? ""
        print("  \(item.url.path)\(size)\(agent)")
        total += item.sizeBytes ?? 0
      }
      print("")
    }
    let suffix = noSizes ? "" : ", \(FileSize.format(total))"
    print("\(items.count) items\(suffix)")
  }
}
