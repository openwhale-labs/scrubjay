import Foundation

public enum FileSize {
  /// Total allocated size of a file, or the recursive total for a directory.
  public static func allocatedSize(at url: URL) -> Int64? {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
    if values.isDirectory != true {
      return values.totalFileAllocatedSize.map(Int64.init)
    }
    guard
      let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
    else {
      return nil
    }
    var total: Int64 = 0
    for case let child as URL in enumerator {
      let childValues = try? child.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
      total += Int64(childValues?.totalFileAllocatedSize ?? 0)
    }
    return total
  }

  /// Human-readable size, e.g. "1.2 MB".
  public static func format(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
