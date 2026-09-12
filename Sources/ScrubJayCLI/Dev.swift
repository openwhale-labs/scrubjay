import ArgumentParser
import Foundation
import ScrubJayKit

struct Dev: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Inspect and clear developer caches.",
    subcommands: [DevList.self, DevClean.self],
    defaultSubcommand: DevList.self
  )
}

struct DevList: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List developer caches present on this machine."
  )

  func run() throws {
    let caches = DevCaches.present()
    guard !caches.isEmpty else {
      print("No known developer caches found.")
      return
    }
    let idWidth = caches.map(\.id.count).max() ?? 0
    for cache in caches {
      let id = cache.id.padding(toLength: idWidth + 2, withPad: " ", startingAt: 0)
      let size = cache.formattedSize
      let paddedSize = size.padding(toLength: max(18, size.count + 2), withPad: " ", startingAt: 0)
      print("\(id)\(paddedSize)\(cache.location.url.path)")
    }
    let total = DevCacheStatus.formattedTotal(caches)
    print("\nTotal: \(total) — clear with `scrubjay dev clean <id ...>`")
  }
}

struct DevClean: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "clean",
    abstract: "Move the given caches to the Trash. Everything is re-fetched or rebuilt on demand."
  )

  @Argument(help: "Cache ids from `scrubjay dev list`.")
  var ids: [String]

  @Flag(name: .long, help: "Skip the confirmation prompt.")
  var yes = false

  func run() throws {
    let present = DevCaches.present()
    let byID = Dictionary(uniqueKeysWithValues: present.map { ($0.id, $0) })

    var selected: [DevCacheStatus] = []
    for id in ids {
      guard let cache = byID[id] else {
        let known = present.map(\.id).joined(separator: ", ")
        throw ValidationError("Unknown cache id \"\(id)\". Present on this machine: \(known)")
      }
      selected.append(cache)
    }

    let total = DevCacheStatus.formattedTotal(selected)
    for cache in selected {
      print("  \(cache.location.url.path) (\(cache.formattedSize))")
    }
    print("")
    if !yes {
      print(
        "Move \(selected.count) cache directories (\(total)) to the Trash? [y/N] ",
        terminator: "")
      let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
      guard answer == "y" || answer == "yes" else {
        print("Cancelled. Nothing was removed.")
        return
      }
    }

    var failures = 0
    for cache in selected {
      do {
        try Trasher.trash(cache.location.url)
        print("  trashed  \(cache.location.url.path)")
      } catch {
        failures += 1
        print("  FAILED   \(cache.location.url.path): \(error.localizedDescription)")
      }
    }
    if failures > 0 { throw ExitCode.failure }
    print("\nDone. \(total) moved to the Trash.")
  }
}
