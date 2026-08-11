import ArgumentParser
import Foundation
import ScrubJayKit

@main
struct ScrubJay: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "scrubjay",
    abstract: "Uninstall Mac apps and the files they leave behind.",
    subcommands: [Apps.self, Scan.self, Remove.self, Dev.self, Orphans.self, Startup.self],
    defaultSubcommand: Apps.self
  )
}

extension Confidence: ExpressibleByArgument {
  public init?(argument: String) {
    switch argument.lowercased() {
    case "low": self = .low
    case "medium": self = .medium
    case "high": self = .high
    case "certain": self = .certain
    default: return nil
    }
  }

  var label: String {
    switch self {
    case .low: "low"
    case .medium: "medium"
    case .high: "high"
    case .certain: "certain"
    }
  }
}

/// Resolve a user-supplied query to a single installed app.
func resolveApp(query: String, among apps: [InstalledApp]) throws -> InstalledApp {
  let lowered = query.lowercased()
  if let exact = apps.first(where: {
    $0.bundleID.lowercased() == lowered || $0.name.lowercased() == lowered
  }) {
    return exact
  }
  let candidates = apps.filter {
    $0.bundleID.lowercased().contains(lowered) || $0.name.lowercased().contains(lowered)
  }
  switch candidates.count {
  case 1:
    return candidates[0]
  case 0:
    throw ValidationError("No installed app matches \"\(query)\".")
  default:
    let names = candidates.map { "  \($0.name) (\($0.bundleID))" }.joined(separator: "\n")
    throw ValidationError("\"\(query)\" is ambiguous. Matches:\n\(names)")
  }
}
