import Foundation

/// The ScrubJay privileged helper: a launchd daemon registered through
/// SMAppService, reachable only over XPC from the signed ScrubJay app.
/// It has exactly one capability — moving system-domain leftovers into the
/// calling user's Trash. Nothing is ever deleted permanently.
///
/// The security boundary lives here, not in the client: the destination and
/// the resulting ownership are derived from the connection's own audit
/// token, and every source path is re-validated against the helper's own
/// rules. A compromised or buggy client cannot widen either.
final class HelperService: NSObject, ScrubJayHelperProtocol {
  /// Identity of the peer, established by the XPC layer rather than claimed
  /// in the request.
  private let peerUID: uid_t
  private let peerGID: gid_t

  init(peerUID: uid_t, peerGID: gid_t) {
    self.peerUID = peerUID
    self.peerGID = peerGID
  }

  func version(reply: @escaping (String) -> Void) {
    reply(HelperConstants.version)
  }

  func trashSystemItems(
    paths: [String], reply: @escaping ([String: String]) -> Void
  ) {
    var failures: [String: String] = [:]
    let fm = FileManager.default

    guard let trash = trashDirectory() else {
      reply(Dictionary(uniqueKeysWithValues: paths.map { ($0, "no Trash for the calling user") }))
      scheduleExit()
      return
    }

    for path in paths {
      // Authorize and act on the same resolved path — no gap between the
      // check and the move for a symlink swap to slip through.
      guard let source = resolvedAllowedSource(path) else {
        failures[path] = "outside the allowed system locations"
        continue
      }
      var destination = trash.appendingPathComponent(source.lastPathComponent)
      var counter = 1
      while fm.fileExists(atPath: destination.path) {
        counter += 1
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
        destination = trash.appendingPathComponent(name)
      }
      do {
        try fm.moveItem(at: source, to: destination)
        if let failure = chownRecursively(destination) {
          failures[path] = failure
        }
      } catch {
        failures[path] = error.localizedDescription
      }
    }
    reply(failures)
    scheduleExit()
  }

  // MARK: Policy

  /// The calling user's Trash, resolved from their home directory. Never
  /// taken from the request.
  private func trashDirectory() -> URL? {
    guard let entry = getpwuid(peerUID), let dir = entry.pointee.pw_dir else { return nil }
    let home = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
      .resolvingSymlinksInPath()
    let trash = home.appendingPathComponent(".Trash", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: trash.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      return nil
    }
    return trash
  }

  /// A source is acceptable only when it resolves to a real, non-symlink
  /// item that sits at least one level below one of the allowed prefixes,
  /// is not itself a search root, and — under /Applications — is an app
  /// bundle. Returns the resolved URL to act on.
  private func resolvedAllowedSource(_ path: String) -> URL? {
    let resolved = URL(fileURLWithPath: path).standardizedFileURL
      .resolvingSymlinksInPath()
    let full = resolved.path

    // A symlink must never be followed into a privileged move.
    var status = stat()
    guard lstat(full, &status) == 0, (status.st_mode & S_IFMT) != S_IFLNK else { return nil }

    guard let prefix = HelperConstants.allowedPrefixes.first(where: { full.hasPrefix($0) }) else {
      return nil
    }
    let relative = String(full.dropFirst(prefix.count))
    guard !relative.isEmpty else { return nil }

    if prefix == "/Applications/" {
      // Only whole app bundles, never their innards or loose files.
      guard !relative.contains("/"), resolved.pathExtension == "app" else { return nil }
      return resolved
    }

    // Under /Library: never a search root itself (…/Caches), always a leaf
    // owned by some app inside one (…/Caches/com.example.app).
    guard relative.contains("/") else { return nil }
    guard !HelperConstants.protectedSystemPaths.contains(full) else { return nil }
    return resolved
  }

  // MARK: Ownership

  /// Hand ownership of the moved tree to the calling user.
  ///
  /// Uses `lchown`, never `chown`: `chown(2)` follows symbolic links, so a
  /// link inside a removed bundle could otherwise redirect a root-privileged
  /// ownership change onto an arbitrary file elsewhere on the system.
  ///
  /// - Returns: a message when the item may be unusable from the Trash.
  private func chownRecursively(_ url: URL) -> String? {
    var failed = 0
    if lchown(url.path, peerUID, peerGID) != 0 {
      return "moved to the Trash, but still owned by root"
    }
    let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
    while let child = enumerator?.nextObject() as? URL {
      if lchown(child.path, peerUID, peerGID) != 0 {
        failed += 1
      }
    }
    return failed == 0 ? nil : "moved to the Trash; \(failed) items still owned by root"
  }

  /// Single-shot: exit after servicing so the next request always runs the
  /// binary currently embedded in the app; launchd respawns on demand.
  private func scheduleExit() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      exit(0)
    }
  }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
  func listener(
    _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    // Only the ScrubJay app signed by our team may talk to this helper.
    connection.setCodeSigningRequirement(
      "anchor apple generic and identifier \"dev.openwhale.scrubjay\" "
        + "and certificate leaf[subject.OU] = \"67ULUSQ947\"")
    // Root may not ask the helper to act as itself: the Trash and the
    // resulting ownership follow the connecting user.
    let uid = connection.effectiveUserIdentifier
    guard uid != 0 else { return false }
    connection.exportedInterface = NSXPCInterface(with: ScrubJayHelperProtocol.self)
    connection.exportedObject = HelperService(
      peerUID: uid, peerGID: connection.effectiveGroupIdentifier)
    connection.resume()
    return true
  }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
