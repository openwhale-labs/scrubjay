import Foundation

public enum FileSize {
  /// Total allocated size of a file, or the recursive total for a directory.
  /// `onError` identifies unreadable paths when a caller needs to distinguish
  /// a partial sum from a complete measurement.
  public static func allocatedSize(
    at url: URL, onError: ((URL, Error) -> Void)? = nil
  ) -> Int64? {
    let keys: Set<URLResourceKey> = [
      .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey
    ]
    let values: URLResourceValues
    do {
      values = try url.resourceValues(forKeys: keys)
    } catch {
      onError?(url, error)
      return nil
    }
    if values.isDirectory != true {
      if values.isRegularFile == false && values.isSymbolicLink == false { return 0 }
      return values.totalFileAllocatedSize.map(Int64.init)
    }
    guard
      let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: Array(keys),
        errorHandler: { failedURL, error in
          onError?(failedURL, error)
          return true
        })
    else {
      onError?(url, CocoaError(.fileReadUnknown))
      return nil
    }
    var total: Int64 = 0
    for case let child as URL in enumerator {
      do {
        let childValues = try child.resourceValues(forKeys: keys)
        // Directory resource values do not carry an allocated file size;
        // their readable contents are counted by the enumerator instead.
        if childValues.isDirectory == true { continue }
        // Sockets and pipes have no file payload or allocated-size value.
        if childValues.isRegularFile == false && childValues.isSymbolicLink == false { continue }
        if let size = childValues.totalFileAllocatedSize {
          total += Int64(size)
        } else {
          onError?(child, CocoaError(.fileReadUnknown))
        }
      } catch {
        onError?(child, error)
      }
    }
    return total
  }

  /// Human-readable size, e.g. "1.2 MB".
  public static func format(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
