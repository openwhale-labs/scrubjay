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

  public init(url: URL, kind: LeftoverKind, confidence: Confidence, sizeBytes: Int64?) {
    self.url = url
    self.kind = kind
    self.confidence = confidence
    self.sizeBytes = sizeBytes
  }
}
