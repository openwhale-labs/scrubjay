import Foundation

/// Moves files to the Trash. ScrubJay never deletes anything permanently —
/// every removal must be recoverable from the Trash.
public enum Trasher {
  public enum TrashError: Error, Equatable {
    /// Refused to trash a path that is a protected location (home directory,
    /// the Library folder itself, or a filesystem root).
    case protectedPath(String)
  }

  /// Paths that must never be trashed, even if matching logic goes wrong.
  /// Symlinks are resolved first so a link cannot smuggle a protected
  /// target past the check.
  static func isProtected(_ url: URL) -> Bool {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let protected: Set<String> = [
      "/", home,
      home + "/Library",
      home + "/Documents",
      home + "/Desktop",
      home + "/Downloads",
      "/Applications",
      "/Library",
      "/System",
      "/Users"
    ]
    return protected.contains(path)
  }

  /// True when macOS refused the move for lack of permission. For an app
  /// bundle this is the App Management privacy setting (System Settings ›
  /// Privacy & Security › App Management, macOS 13+): the system posts only
  /// a notification, never a dialog, and offers no API to request the
  /// permission — so callers must recognise the error and point the user at
  /// the setting themselves.
  public static func isPermissionDenied(_ error: Error) -> Bool {
    var next: NSError? = error as NSError
    while let current = next {
      if current.domain == NSCocoaErrorDomain,
        current.code == CocoaError.fileWriteNoPermission.rawValue {
        return true
      }
      if current.domain == NSPOSIXErrorDomain,
        current.code == Int(EPERM) || current.code == Int(EACCES) {
        return true
      }
      next = current.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return false
  }

  /// Move a file or directory to the Trash.
  ///
  /// - Returns: the item's new location inside the Trash, when provided by
  ///   the system.
  @discardableResult
  public static func trash(_ url: URL) throws -> URL? {
    guard !isProtected(url) else {
      throw TrashError.protectedPath(url.path)
    }
    var trashedURL: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
    return trashedURL as URL?
  }
}
