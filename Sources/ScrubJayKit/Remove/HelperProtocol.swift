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

  /// An allow-list, not a prefix filter: the helper moves only direct
  /// children of these directories — the same roots the scanner reports —
  /// so nothing else under /Library is reachable. Keychains, Security,
  /// Extensions and friends are absent by construction.
  public static let allowedLibraryRoots = [
    "/Library/Application Support",
    "/Library/Caches",
    "/Library/Preferences",
    "/Library/LaunchAgents",
    "/Library/LaunchDaemons",
    "/Library/PrivilegedHelperTools",
  ]

  /// App bundles live here; only whole `.app` bundles qualify. Covers
  /// root-owned installs (Tunnelblick chowns itself to root).
  public static let applicationsRoot = "/Applications"
}
