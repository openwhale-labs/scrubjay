import Foundation

/// A file or directory believed to belong to an app.
public struct LeftoverItem: Sendable, Hashable, Identifiable {
  public var id: URL { url }

  public let url: URL
  /// Which search root produced this item.
  public let kind: LeftoverKind
  public let confidence: Confidence
  /// Total allocated size in bytes, when computed.
  public let sizeBytes: Int64?
  /// Set for launch-agent plists; removal unloads the agent first.
  public let launchAgent: LaunchAgentInfo?

  public init(
    url: URL, kind: LeftoverKind, confidence: Confidence, sizeBytes: Int64?,
    launchAgent: LaunchAgentInfo? = nil
  ) {
    self.url = url
    self.kind = kind
    self.confidence = confidence
    self.sizeBytes = sizeBytes
    self.launchAgent = launchAgent
  }
}
