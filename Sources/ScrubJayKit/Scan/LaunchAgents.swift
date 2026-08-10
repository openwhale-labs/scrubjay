import Foundation

/// A user launch agent found among an app's leftovers.
public struct LaunchAgentInfo: Sendable, Hashable {
  /// The `Label` key of the agent's plist, used with launchctl.
  public let label: String
  /// Whether the agent is currently loaded in the user's launchd domain.
  public let isLoaded: Bool

  public init(label: String, isLoaded: Bool) {
    self.label = label
    self.isLoaded = isLoaded
  }

  /// Whether the agent's Label belongs to the given app. Unloading is a
  /// behavior change beyond the Trash model, so it only happens when the
  /// Label itself carries the app's bundle identifier — a matched *file
  /// name* is not enough.
  public func belongsTo(bundleID: String) -> Bool {
    let label = label.lowercased()
    let bundleID = bundleID.lowercased()
    return label == bundleID || label.hasPrefix(bundleID + ".")
  }
}

/// Reads and unloads user launch agents. Trashing an agent's plist alone is
/// not enough: the loaded job would keep running until logout, so removal
/// unloads it first.
public enum LaunchAgents {
  /// Parse an agent plist and check its load state.
  public static func info(forPlistAt url: URL) -> LaunchAgentInfo? {
    guard
      let data = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let label = (plist as? [String: Any])?["Label"] as? String
    else {
      return nil
    }
    return LaunchAgentInfo(label: label, isLoaded: isLoaded(label: label))
  }

  public static func isLoaded(label: String) -> Bool {
    launchctl(["print", "gui/\(getuid())/\(label)"])
  }

  /// Unload the agent from the user's launchd domain.
  ///
  /// - Returns: true when launchctl reported success.
  @discardableResult
  public static func unload(label: String) -> Bool {
    launchctl(["bootout", "gui/\(getuid())/\(label)"])
  }

  private static func launchctl(_ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return false
    }
    process.waitUntilExit()
    return process.terminationStatus == 0
  }
}
