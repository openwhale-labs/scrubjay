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

  @Flag(
    name: .customLong("include-chat-data"),
    help: "For messaging apps, also remove data folders that hold chat history.")
  var includeChatData = false

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
    var items = scanner.scan(for: app.identity, amongInstalled: apps.map(\.identity))
      .filter { $0.confidence >= minConfidence }
    // Chat history is irreplaceable: for messaging apps, data folders stay
    // unless explicitly included.
    if SensitiveApps.holdsChatHistory(bundleID: app.bundleID), !includeChatData {
      let skipped = items.filter { SensitiveApps.dataKinds.contains($0.kind) }
      items.removeAll { SensitiveApps.dataKinds.contains($0.kind) }
      if !skipped.isEmpty {
        print(
          "Keeping \(skipped.count) data folders that may hold chat history "
            + "(pass --include-chat-data to remove them):")
        for item in skipped {
          print("  kept  \(item.url.path)")
        }
        print("")
      }
    }

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

    // System-domain items need the privileged helper, which lives in the
    // app — the CLI cannot remove them.
    let systemItems = items.filter { LeftoverCatalog.isSystemPath($0.url) }
    if !systemItems.isEmpty {
      print("Skipping \(systemItems.count) system items — remove these in the ScrubJay app:")
      for item in systemItems {
        print("  skipped  \(item.url.path)")
      }
      print("")
      items.removeAll { LeftoverCatalog.isSystemPath($0.url) }
    }

    var failures = 0
    for item in items {
      if let agent = item.launchAgent, agent.isLoaded, agent.belongsTo(bundleID: app.bundleID) {
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
    if !leftoversOnly,
      let cask = Homebrew.caskToken(
        forAppNamed: app.bundleURL.lastPathComponent, in: Homebrew.installedCasks())
    {
      print("Installed via Homebrew — run `brew uninstall --cask \(cask)` to clear its records.")
    }
  }
}
