import Foundation

/// An application bundle discovered on disk.
public struct InstalledApp: Sendable, Hashable, Identifiable {
  public var id: String { bundleID }

  /// The bundle identifier, e.g. `com.google.Chrome`.
  public let bundleID: String
  /// Display name, e.g. "Google Chrome".
  public let name: String
  /// Location of the `.app` bundle.
  public let bundleURL: URL
  /// `CFBundleShortVersionString`, if present.
  public let version: String?
  /// Apps with a `com.apple.` bundle identifier are protected from removal.
  public var isAppleApp: Bool { bundleID.hasPrefix("com.apple.") }

  public init(bundleID: String, name: String, bundleURL: URL, version: String?) {
    self.bundleID = bundleID
    self.name = name
    self.bundleURL = bundleURL
    self.version = version
  }

  /// The identity used for leftover matching.
  public var identity: AppIdentity {
    AppIdentity(bundleID: bundleID, name: name)
  }
}
