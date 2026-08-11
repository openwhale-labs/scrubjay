import Foundation
import ScrubJayKit
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
  /// System Settings › Login Items on first registration; while approval is
  /// pending, `register()` throws "Operation not permitted" — that is part
  /// of the normal flow, not a failure.
  ///
  /// - Returns: an error message only for real failures.
  func register() -> String? {
    let thrown: (any Error)?
    do {
      try service.register()
      thrown = nil
    } catch {
      thrown = error
    }
    refreshStatus()
    if status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
      return nil
    }
    if status == .enabled {
      return nil
    }
    return thrown?.localizedDescription
  }

  func unregister() throws {
    try service.unregister()
    refreshStatus()
  }

  /// Read the background task management database through the helper.
  func readBackgroundItems() async -> String? {
    await withHelper { proxy, finish in
      proxy.readBackgroundItems { finish($0) }
    } onFailure: {
      nil
    }
  }

  /// Open a connection, hand the proxy to `body`, and resume exactly once —
  /// the XPC error handler and the reply are mutually exclusive in normal
  /// operation, but nothing in the API guarantees it.
  private func withHelper<T: Sendable>(
    _ body: @escaping (ScrubJayHelperProtocol, @escaping (T) -> Void) -> Void,
    onFailure: @escaping () -> T
  ) async -> T {
    let connection = NSXPCConnection(
      machServiceName: HelperConstants.machServiceName, options: .privileged)
    connection.remoteObjectInterface = NSXPCInterface(with: ScrubJayHelperProtocol.self)
    connection.setCodeSigningRequirement(
      "anchor apple generic and identifier \"\(HelperConstants.machServiceName)\" "
        + "and certificate leaf[subject.OU] = \"67ULUSQ947\"")
    connection.resume()
    defer { connection.invalidate() }

    let once = Once()
    return await withCheckedContinuation { continuation in
      guard
        let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
          once.run { continuation.resume(returning: onFailure()) }
        }) as? ScrubJayHelperProtocol
      else {
        once.run { continuation.resume(returning: onFailure()) }
        return
      }
      body(proxy) { value in
        once.run { continuation.resume(returning: value) }
      }
    }
  }

  /// Move system-domain items into the user's Trash via the helper.
  ///
  /// - Returns: failed paths mapped to error descriptions.
  func trashSystemItems(_ urls: [URL]) async -> [String: String] {
    await withHelper { proxy, finish in
      proxy.trashSystemItems(paths: urls.map(\.path)) { finish($0) }
    } onFailure: {
      Dictionary(uniqueKeysWithValues: urls.map { ($0.path, "helper connection failed") })
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
