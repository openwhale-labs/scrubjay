import AppKit
import ArgumentParser
import Foundation
import ScrubJayKit

struct Remove: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Uninstall an app: move it and its leftovers to the Trash.",
    discussion: """
      Nothing is deleted permanently — every item goes to the Trash. \
      Loosely matched files (low confidence) are excluded unless you lower \
      --min-confidence yourself.
      """
  )

  @Argument(help: "App name or bundle identifier (fuzzy).")
  var query: String

  @Flag(name: .long, help: "Keep the app; only remove its leftover files.")
  var leftoversOnly = false

  @Option(name: .long, help: "Include results down to this confidence: low|medium|high|certain.")
  var minConfidence: Confidence = .medium

  @Flag(name: .long, help: "Skip the confirmation prompt.")
  var yes = false

  func run() throws {
    let apps = AppInventory.discoverApps()
    let app = try resolveApp(query: query, among: apps)

    guard !app.isAppleApp else {
      throw ValidationError("Refusing to remove an Apple application (\(app.bundleID)).")
    }
    let running = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
      .isEmpty
    if !leftoversOnly, running {
      throw ValidationError("\(app.name) is running. Quit it first.")
    }

    let scanner = LeftoverScanner.forCurrentUser()
    let items = scanner.scan(for: app.identity, amongInstalled: apps.map(\.identity))
      .filter { $0.confidence >= minConfidence }

    var total = items.compactMap(\.sizeBytes).reduce(0, +)
    print("\(app.name) (\(app.bundleID))\n")
    if !leftoversOnly {
      let bundleSize = FileSize.allocatedSize(at: app.bundleURL)
      total += bundleSize ?? 0
      print("  \(app.bundleURL.path)  (\(bundleSize.map(FileSize.format) ?? "?"))")
    }
    for item in items {
      let size = item.sizeBytes.map { "  (\(FileSize.format($0)))" } ?? ""
      print("  \(item.url.path)\(size)")
    }
    let count = items.count + (leftoversOnly ? 0 : 1)
    guard count > 0 else {
      print("Nothing to remove.")
      return
    }
    print("")

    if !yes {
      print("Move \(count) items (\(FileSize.format(total))) to the Trash? [y/N] ", terminator: "")
      let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
      guard answer == "y" || answer == "yes" else {
        print("Cancelled. Nothing was removed.")
        return
      }
    }

    var failures = 0
    for item in items {
      if let agent = item.launchAgent, agent.isLoaded {
        let unloaded = LaunchAgents.unload(label: agent.label)
        print("  \(unloaded ? "unloaded" : "still loaded")  \(agent.label)")
      }
      do {
        try Trasher.trash(item.url)
        print("  trashed  \(item.url.path)")
      } catch {
        failures += 1
        print("  FAILED   \(item.url.path): \(error.localizedDescription)")
      }
    }
    if !leftoversOnly {
      do {
        try Trasher.trash(app.bundleURL)
        print("  trashed  \(app.bundleURL.path)")
      } catch {
        failures += 1
        print("  FAILED   \(app.bundleURL.path): \(error.localizedDescription)")
      }
    }
    if failures > 0 {
      throw ExitCode.failure
    }
    print("\nDone. Items are in the Trash and can be restored from there.")
  }
}
