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
    let app = try resolveApp(query: query)
    print("\(app.name) (\(app.bundleID)) — \(app.bundleURL.path)\n")

    let scanner = LeftoverScanner.forCurrentUser()
    let items = scanner.scan(for: app.identity, computeSizes: !noSizes)
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
        print("  \(item.url.path)\(size)")
        total += item.sizeBytes ?? 0
      }
      print("")
    }
    let suffix = noSizes ? "" : ", \(FileSize.format(total))"
    print("\(items.count) items\(suffix)")
  }
}
