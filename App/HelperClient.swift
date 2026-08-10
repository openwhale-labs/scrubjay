import Foundation
import ServiceManagement

/// App-side face of the privileged helper: registration through
/// SMAppService and the XPC call to move system-domain items to the Trash.
@MainActor
@Observable
final class HelperClient {
  private let service = SMAppService.daemon(plistName: HelperConstants.plistName)

  var status: SMAppService.Status = .notRegistered

  func refreshStatus() {
    status = service.status
  }

  var statusDescription: String {
    switch status {
    case .enabled: "enabled"
    case .requiresApproval: "waiting for approval in System Settings"
    case .notRegistered: "not registered"
    case .notFound: "not found"
    @unknown default: "unknown"
    }
  }

  /// Register the daemon. macOS asks the user to approve it in
  /// System Settings › Login Items on first registration.
  func register() throws {
    try service.register()
    refreshStatus()
    if status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
  }

  func unregister() throws {
    try service.unregister()
    refreshStatus()
  }

  /// Move system-domain items into the user's Trash via the helper.
  ///
  /// - Returns: failed paths mapped to error descriptions.
  func trashSystemItems(_ urls: [URL]) async -> [String: String] {
    let connection = NSXPCConnection(
      machServiceName: HelperConstants.machServiceName, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: ScrubJayHelperProtocol.self)
    connection.resume()
    defer { connection.invalidate() }

    let trashDirectory = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".Trash").path

    // The XPC error handler and the reply are mutually exclusive in normal
    // operation, but nothing in the API guarantees it — resume exactly once.
    let once = Once()
    return await withCheckedContinuation { continuation in
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
          once.run {
            continuation.resume(
              returning: Dictionary(
                uniqueKeysWithValues: urls.map { ($0.path, error.localizedDescription) }))
          }
        }) as? ScrubJayHelperProtocol
      else {
        once.run {
          continuation.resume(
            returning: Dictionary(
              uniqueKeysWithValues: urls.map { ($0.path, "helper connection failed") }))
        }
        return
      }
      proxy.trashSystemItems(
        paths: urls.map(\.path), trashDirectory: trashDirectory,
        uid: getuid(), gid: getgid()
      ) { failures in
        once.run { continuation.resume(returning: failures) }
      }
    }
  }
}

/// Executes a closure at most once, from any thread.
private final class Once: @unchecked Sendable {
  private let lock = NSLock()
  private var done = false

  func run(_ body: () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    guard !done else { return }
    done = true
    body()
  }
}
