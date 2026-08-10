import Foundation

/// XPC surface of the privileged helper. Kept minimal: version for the
/// handshake, and one operation — move system-domain items into the user's
/// Trash. The helper never deletes permanently.
@objc public protocol ScrubJayHelperProtocol {
  func version(reply: @escaping (String) -> Void)

  /// Move each path into the calling user's Trash and hand it their
  /// ownership, so the items stay visible and restorable.
  ///
  /// The destination and the resulting ownership are derived by the helper
  /// from the connection's audit token — deliberately not parameters, so a
  /// client cannot redirect a root-privileged move.
  ///
  /// - Returns via reply: failed paths mapped to error descriptions; empty
  ///   dictionary means every item landed in the Trash.
  func trashSystemItems(paths: [String], reply: @escaping ([String: String]) -> Void)
}

public enum HelperConstants {
  public static let machServiceName = "dev.openwhale.scrubjay.helper"
  public static let plistName = "dev.openwhale.scrubjay.helper.plist"
  public static let version = "3"

  /// The helper refuses to touch anything outside these prefixes, and never
  /// the prefix roots themselves. /Applications covers root-owned app
  /// bundles (Tunnelblick installs itself owned by root).
  public static let allowedPrefixes = ["/Library/", "/Applications/"]

  /// System directories the helper never moves as a whole, even though they
  /// sit under an allowed prefix — only their per-app children qualify.
  public static let protectedSystemPaths: Set<String> = [
    "/Library/Application Support", "/Library/Caches", "/Library/Preferences",
    "/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools",
    "/Library/Extensions", "/Library/Frameworks", "/Library/Internet Plug-Ins",
    "/Library/Input Methods", "/Library/Keychains", "/Library/Security",
  ]
}
