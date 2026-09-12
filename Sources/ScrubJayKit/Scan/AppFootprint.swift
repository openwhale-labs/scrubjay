import Foundation

/// One scan snapshot, shared by the app list and removal checklist.
public struct AppFootprint: Sendable {
  public let bundleSize: Int64?
  public let items: [LeftoverItem]
  public let unreadableURLs: [URL]
  public let isBundleOnly: Bool

  public init(
    bundleSize: Int64?, items: [LeftoverItem] = [], unreadableURLs: [URL] = [],
    isBundleOnly: Bool = false
  ) {
    self.bundleSize = bundleSize
    self.items = items
    self.unreadableURLs = Array(Set(unreadableURLs)).sorted { $0.path < $1.path }
    self.isBundleOnly = isBundleOnly
  }

  public var totalSize: Int64 {
    (bundleSize ?? 0) + items.compactMap(\.sizeBytes).reduce(0, +)
  }

  public var isIncomplete: Bool {
    bundleSize == nil || !unreadableURLs.isEmpty || items.contains { $0.sizeBytes == nil }
  }

  public var formattedSize: String {
    let size = FileSize.format(totalSize)
    if isBundleOnly { return "\(size)…" }
    return isIncomplete ? "≥ \(size)" : size
  }

  public static func scan(
    app: InstalledApp, amongInstalled identities: [AppIdentity],
    scanner: LeftoverScanner = .forCurrentUser()
  ) -> AppFootprint {
    var unreadable: [URL] = []
    let items = scanner.scan(for: app.identity, amongInstalled: identities) { url, _ in
      unreadable.append(url)
    }
    let bundleSize = FileSize.allocatedSize(at: app.bundleURL) { url, _ in
      unreadable.append(url)
    }
    return AppFootprint(bundleSize: bundleSize, items: items, unreadableURLs: unreadable)
  }
}

/// Front ends own threading; request tokens reject results superseded by a
/// newer scan or inventory reload, including the initial bundle-only pass.
public struct AppFootprintCache {
  public struct Request: Sendable, Equatable {
    fileprivate let bundleID: String
    fileprivate let revision: Int
  }

  private var revision = 0
  private var requests: [String: Request] = [:]
  private var snapshots: [String: AppFootprint] = [:]

  public init() {}

  public subscript(bundleID: String) -> AppFootprint? { snapshots[bundleID] }

  public mutating func reset() {
    requests = [:]
    snapshots = [:]
  }

  public mutating func beginScan(for bundleID: String) -> Request {
    revision += 1
    let request = Request(bundleID: bundleID, revision: revision)
    requests[bundleID] = request
    return request
  }

  public func isCurrent(_ request: Request) -> Bool {
    requests[request.bundleID] == request
  }

  @discardableResult
  public mutating func publish(_ footprint: AppFootprint, for request: Request) -> Bool {
    guard isCurrent(request) else { return false }
    snapshots[request.bundleID] = footprint
    return true
  }
}
