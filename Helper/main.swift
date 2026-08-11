import Foundation

/// The ScrubJay privileged helper: a launchd daemon registered through
/// SMAppService, reachable only over XPC from the signed ScrubJay app.
/// It has exactly one capability — moving system-domain leftovers into the
/// calling user's Trash. Nothing is ever deleted permanently.
///
/// The security boundary lives here, not in the client. Two properties hold
/// no matter what a caller sends:
///
/// 1. The destination and the resulting ownership come from the connection's
///    own audit token, never from the request.
/// 2. Every filesystem operation runs against file descriptors opened with
///    `O_NOFOLLOW`, never against path strings. A path checked and then used
///    can be swapped in between; a descriptor cannot.
final class HelperService: NSObject, ScrubJayHelperProtocol {
  private let peerUID: uid_t
  private let peerGID: gid_t

  init(peerUID: uid_t, peerGID: gid_t) {
    self.peerUID = peerUID
    self.peerGID = peerGID
  }

  func version(reply: @escaping (String) -> Void) {
    reply(HelperConstants.version)
  }

  /// Read-only: one fixed command, no caller-supplied arguments, no writes.
  func readBackgroundItems(reply: @escaping (String?) -> Void) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sfltool")
    process.arguments = ["dumpbtm"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      reply(nil)
      scheduleExit()
      return
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    reply(process.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil)
    scheduleExit()
  }

  func trashSystemItems(
    paths: [String], reply: @escaping ([String: String]) -> Void
  ) {
    var failures: [String: String] = [:]

    guard let trashFD = openTrashDirectory() else {
      reply(Dictionary(uniqueKeysWithValues: paths.map { ($0, "no Trash for the calling user") }))
      scheduleExit()
      return
    }
    defer { close(trashFD) }

    for path in paths {
      guard let (parent, name) = allowedParentAndName(path) else {
        failures[path] = "outside the allowed system locations"
        continue
      }
      // Open the allow-listed parent itself, so the move is relative to a
      // descriptor rather than to a name that could change under us.
      let parentFD = open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard parentFD >= 0 else {
        failures[path] = "cannot open \(parent)"
        continue
      }
      defer { close(parentFD) }

      // The item itself must not be a symlink.
      var status = stat()
      guard fstatat(parentFD, name, &status, AT_SYMLINK_NOFOLLOW) == 0,
        (status.st_mode & S_IFMT) != S_IFLNK
      else {
        failures[path] = "not a regular file or directory"
        continue
      }

      let destination = availableName(in: trashFD, preferred: name)
      guard renameat(parentFD, name, trashFD, destination) == 0 else {
        failures[path] = String(cString: strerror(errno))
        continue
      }
      let unowned = chownTree(parent: trashFD, name: destination)
      if unowned > 0 {
        failures[path] = "moved to the Trash; \(unowned) items still owned by root"
      }
    }
    reply(failures)
    scheduleExit()
  }

  // MARK: Destination

  /// A descriptor for the calling user's Trash, opened without following
  /// links. Everything downstream is relative to this descriptor, so the
  /// directory cannot be swapped for a symlink after the check.
  private func openTrashDirectory() -> Int32? {
    guard let entry = getpwuid(peerUID), let dir = entry.pointee.pw_dir else { return nil }
    let home = String(cString: dir)
    let homeFD = open(home, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard homeFD >= 0 else { return nil }
    defer { close(homeFD) }
    let trashFD = openat(homeFD, ".Trash", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    return trashFD >= 0 ? trashFD : nil
  }

  /// A name that does not collide inside the Trash.
  private func availableName(in trashFD: Int32, preferred: String) -> String {
    var candidate = preferred
    var counter = 1
    let url = URL(fileURLWithPath: preferred)
    let base = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    while faccessat(trashFD, candidate, F_OK, AT_SYMLINK_NOFOLLOW) == 0 {
      counter += 1
      candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
    }
    return candidate
  }

  // MARK: Source policy

  /// Split a request into (allow-listed parent, item name), or nil when the
  /// item is not a direct child of a directory the helper may touch.
  ///
  /// The parent is compared for equality against the allow-list — the same
  /// system roots the scanner reports — so no prefix trickery widens it.
  private func allowedParentAndName(_ path: String) -> (parent: String, name: String)? {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let name = url.lastPathComponent
    guard !name.isEmpty, name != "/", name != ".", name != ".." else { return nil }
    let parent = url.deletingLastPathComponent().path

    if parent == HelperConstants.applicationsRoot {
      // Whole app bundles only, never their innards or loose files.
      return url.pathExtension == "app" ? (parent, name) : nil
    }
    return HelperConstants.allowedLibraryRoots.contains(parent) ? (parent, name) : nil
  }

  // MARK: Ownership

  /// Hand the moved tree to the calling user, walking it by descriptor and
  /// never following a link: `chown(2)` follows symlinks, so a link inside a
  /// removed bundle could otherwise redirect a root-privileged ownership
  /// change onto an arbitrary file elsewhere on the system.
  ///
  /// - Returns: how many items could not be handed over.
  private func chownTree(parent: Int32, name: String) -> Int {
    var failures = 0
    if fchownat(parent, name, peerUID, peerGID, AT_SYMLINK_NOFOLLOW) != 0 {
      failures += 1
    }
    var status = stat()
    guard fstatat(parent, name, &status, AT_SYMLINK_NOFOLLOW) == 0,
      (status.st_mode & S_IFMT) == S_IFDIR
    else {
      return failures
    }
    let directoryFD = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard directoryFD >= 0 else { return failures + 1 }
    guard let handle = fdopendir(directoryFD) else {
      close(directoryFD)
      return failures + 1
    }
    defer { closedir(handle) }  // closes directoryFD too
    while let entry = readdir(handle) {
      let child = withUnsafePointer(to: entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
          String(cString: $0)
        }
      }
      guard child != ".", child != ".." else { continue }
      failures += chownTree(parent: directoryFD, name: child)
    }
    return failures
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
