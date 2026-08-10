import Foundation

/// XPC surface of the privileged helper. Kept minimal: version for the
/// handshake, and one operation — move system-domain items into the user's
/// Trash. The helper never deletes permanently.
@objc public protocol ScrubJayHelperProtocol {
  func version(reply: @escaping (String) -> Void)

  /// Move each path into `trashDirectory` (the invoking user's ~/.Trash)
  /// and hand ownership to uid/gid so the items are visible and restorable.
  ///
  /// - Returns via reply: failed paths mapped to error descriptions; empty
  ///   dictionary means every item landed in the Trash.
  func trashSystemItems(
    paths: [String], trashDirectory: String, uid: UInt32, gid: UInt32,
    reply: @escaping ([String: String]) -> Void)
}

public enum HelperConstants {
  public static let machServiceName = "com.openwhale.scrubjay.helper"
  public static let plistName = "com.openwhale.scrubjay.helper.plist"
  public static let version = "2"

  /// The helper refuses to touch anything outside these prefixes, and never
  /// the prefix roots themselves. /Applications covers root-owned app
  /// bundles (Tunnelblick installs itself owned by root).
  public static let allowedPrefixes = ["/Library/", "/Applications/"]
}
