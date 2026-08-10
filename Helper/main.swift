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

  /// The calling user's Trash, derived from their home directory.
  ///
  /// The path must be a real directory, never a symlink: a link here would
  /// redirect a root-privileged move anywhere the link points, which is a
  /// privilege-escalation primitive rather than a Trash.
  private func trashDirectory() -> URL? {
    guard let entry = getpwuid(peerUID), let dir = entry.pointee.pw_dir else { return nil }
    let home = URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    let trash = home.appendingPathComponent(".Trash", isDirectory: true)
    guard isRealDirectoryWithoutLinks(trash.path) else { return nil }
    return trash
  }

  /// True when the path is a directory and no component of it is a symlink,
  /// so following it cannot leave the intended location.
  private func isRealDirectoryWithoutLinks(_ path: String) -> Bool {
    var status = stat()
    guard lstat(path, &status) == 0, (status.st_mode & S_IFMT) == S_IFDIR else { return false }
    return hasNoSymlinkComponents(path)
  }

  /// True when the fully resolved path equals the standardized path — i.e.
  /// no component along the way is a symbolic link. Authorization and the
  /// move then act on the same real location.
  private func hasNoSymlinkComponents(_ path: String) -> Bool {
    guard let resolved = realpath(path, nil) else { return false }
    defer { free(resolved) }
    return String(cString: resolved) == URL(fileURLWithPath: path).standardizedFileURL.path
  }

  /// A source qualifies only when it is a direct child of one of the
  /// allow-listed roots, contains no symlinked path component, and — under
  /// /Applications — is a whole `.app` bundle.
  private func resolvedAllowedSource(_ path: String) -> URL? {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let full = url.path

    // No component may be a link: a link anywhere in the path could point
    // the privileged move at something else entirely.
    guard hasNoSymlinkComponents(full) else { return nil }

    let parent = url.deletingLastPathComponent().path
    guard !url.lastPathComponent.isEmpty, url.lastPathComponent != "/" else { return nil }

    if parent == HelperConstants.applicationsRoot {
      // Whole app bundles only, never their innards or loose files.
      return url.pathExtension == "app" ? url : nil
    }
    // Direct children of the scanner's own system roots, nothing else.
    return HelperConstants.allowedLibraryRoots.contains(parent) ? url : nil
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
