import Foundation

/// The ScrubJay privileged helper: a launchd daemon registered through
/// SMAppService, reachable only over XPC from the signed ScrubJay app.
/// It has exactly one capability — moving system-domain leftovers into the
/// requesting user's Trash. Nothing is ever deleted permanently.
final class HelperService: NSObject, ScrubJayHelperProtocol {
  func version(reply: @escaping (String) -> Void) {
    reply(HelperConstants.version)
  }

  func trashSystemItems(
    paths: [String], trashDirectory: String, uid: UInt32, gid: UInt32,
    reply: @escaping ([String: String]) -> Void
  ) {
    var failures: [String: String] = [:]
    let fm = FileManager.default

    for path in paths {
      guard isAllowed(path) else {
        failures[path] = "outside the allowed system locations"
        continue
      }
      let source = URL(fileURLWithPath: path)
      var destination = URL(fileURLWithPath: trashDirectory)
        .appendingPathComponent(source.lastPathComponent)
      var counter = 1
      while fm.fileExists(atPath: destination.path) {
        counter += 1
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
        destination = URL(fileURLWithPath: trashDirectory).appendingPathComponent(name)
      }
      do {
        try fm.moveItem(at: source, to: destination)
        chownRecursively(destination, uid: uid, gid: gid)
      } catch {
        failures[path] = error.localizedDescription
      }
    }
    reply(failures)
    // Single-shot: exit after servicing so the next request always runs the
    // binary currently embedded in the app; launchd respawns on demand.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      exit(0)
    }
  }

  /// Only proper children of the allowed prefixes. A standardized path has
  /// no trailing slash, so the prefix root itself ("/Library") never
  /// matches "/Library/".
  private func isAllowed(_ path: String) -> Bool {
    let resolved = URL(fileURLWithPath: path).standardizedFileURL
      .resolvingSymlinksInPath().path
    return HelperConstants.allowedPrefixes.contains { prefix in
      resolved.hasPrefix(prefix) && resolved.count > prefix.count
    }
  }

  private func chownRecursively(_ url: URL, uid: UInt32, gid: UInt32) {
    chown(url.path, uid_t(uid), gid_t(gid))
    let enumerator = FileManager.default.enumerator(
      at: url, includingPropertiesForKeys: nil)
    while let child = enumerator?.nextObject() as? URL {
      chown(child.path, uid_t(uid), gid_t(gid))
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
    connection.exportedInterface = NSXPCInterface(with: ScrubJayHelperProtocol.self)
    connection.exportedObject = HelperService()
    connection.resume()
    return true
  }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
