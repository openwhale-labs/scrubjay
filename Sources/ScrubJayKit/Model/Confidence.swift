import Foundation

/// How certain the scanner is that a file belongs to a given app.
///
/// Confidence drives the default selection in any UI: `certain` and `high`
/// items are safe to preselect, `medium` needs a glance, `low` must never be
/// selected automatically.
public enum Confidence: Int, Sendable, Comparable, CaseIterable {
  /// Loose name similarity only. Never auto-selected.
  case low = 0
  /// Exact (normalized) app-name match. Name collisions are possible.
  case medium = 1
  /// Entry name is prefixed by the app's bundle identifier.
  case high = 2
  /// Entry name is exactly the bundle identifier, or the bundle identifier
  /// plus a well-known suffix such as `.plist` or `.savedState`.
  case certain = 3

  public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
