import Foundation

/// A login item, launch agent, or daemon registered in macOS's background
/// task management database.
public struct BackgroundItem: Sendable, Hashable, Identifiable {
  public var id: String { identifier }

  /// The database's own identifier, e.g. `4.net.tunnelblick.launcher`.
  public let identifier: String
  public let name: String
  /// Developer or team name, when the database records one.
  public let developer: String?
  /// `login item`, `daemon`, `agent`, … as reported by the database.
  public let kind: String
  public let isEnabled: Bool
  /// Absolute location of the item, resolved through its parent app when
  /// the database stores a bundle-relative path.
  public let url: URL?
  /// Identifier of the app this item belongs to.
  public let parentIdentifier: String?

  public init(
    identifier: String, name: String, developer: String?, kind: String,
    isEnabled: Bool, url: URL?, parentIdentifier: String?
  ) {
    self.identifier = identifier
    self.name = name
    self.developer = developer
    self.kind = kind
    self.isEnabled = isEnabled
    self.url = url
    self.parentIdentifier = parentIdentifier
  }
}

/// Why a background item is considered stale.
public enum StaleReason: String, Sendable {
  /// The app it belongs to is sitting in the Trash.
  case appInTrash
  /// Nothing exists at the recorded location any more.
  case appMissing
}

public struct StaleBackgroundItem: Sendable, Hashable, Identifiable {
  public var id: String { item.identifier }
  public let item: BackgroundItem
  public let reason: StaleReason
}

/// Reads macOS's background task management database — the list behind
/// System Settings › General › Login Items & Extensions.
///
/// Apps that were dragged to the Trash leave their login items registered
/// and switched on. macOS keeps the record and even follows the bundle into
/// the Trash, so the entry lingers with nothing behind it.
public enum BackgroundItems {
  /// Read the database via `sfltool dumpbtm`. Returns nil when the caller
  /// lacks the privileges to read it.
  public static func readDatabase() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sfltool")
    process.arguments = ["dumpbtm"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, !data.isEmpty else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// The account whose sections matter. Under sudo the process runs as
  /// root, but the startup items belong to the user who invoked it.
  public static func callerUID(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int {
    environment["SUDO_UID"].flatMap(Int.init) ?? Int(getuid())
  }

  /// Parse `sfltool dumpbtm` output.
  ///
  /// Entries store either an absolute `file://` URL or a path relative to
  /// their parent app's bundle, so parents are resolved first and children
  /// joined onto them.
  ///
  /// The dump covers every account on the machine, in per-user sections.
  /// Only the caller's own section and the system ones (UID 0 and -2, whose
  /// /Library paths anyone can read) are kept: another user's home is not
  /// readable from here, so their items cannot be told apart from missing
  /// ones — and they are not this user's to clean up anyway.
  public static func parse(dump: String, uid: Int = Int(getuid())) -> [BackgroundItem] {
    let keptUIDs: Set<Int> = [uid, 0, -2]
    var records: [[String: String]] = []
    var current: [String: String] = [:]
    var sectionKept = true

    for line in dump.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("Records for UID ") {
        if !current.isEmpty, sectionKept { records.append(current) }
        current = [:]
        let fields = trimmed.split(separator: " ")
        sectionKept = fields.count > 3 && Int(fields[3]).map(keptUIDs.contains) == true
        continue
      }
      if trimmed.hasPrefix("UUID:") {
        if !current.isEmpty, sectionKept { records.append(current) }
        current = [:]
      }
      guard let colon = trimmed.firstIndex(of: ":") else { continue }
      let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
      var value = String(trimmed[trimmed.index(after: colon)...])
        .trimmingCharacters(in: .whitespaces)
      if value == "(null)" { value = "" }
      if !key.isEmpty { current[key] = value }
    }
    if !current.isEmpty, sectionKept { records.append(current) }

    // Absolute URLs first, so relative children can be joined onto them.
    var absolute: [String: URL] = [:]
    for record in records {
      guard let identifier = record["Identifier"], !identifier.isEmpty,
        let raw = record["URL"], raw.hasPrefix("file://"),
        let url = URL(string: raw)
      else { continue }
      absolute[identifier] = url.standardizedFileURL
    }

    return records.compactMap { record in
      guard let identifier = record["Identifier"], !identifier.isEmpty,
        let name = record["Name"], !name.isEmpty
      else { return nil }
      let kind = (record["Type"] ?? "").split(separator: " ").first.map(String.init) ?? "item"
      // "developer" rows only group an app's items; they have no location.
      guard kind != "developer" else { return nil }

      let parent = record["Parent Identifier"].flatMap { $0.isEmpty ? nil : $0 }
      let url = resolve(record["URL"] ?? "", parent: parent, absolute: absolute)
      let developer = record["Developer Name"].flatMap { $0.isEmpty ? nil : $0 }

      return BackgroundItem(
        identifier: identifier, name: name, developer: developer, kind: kind,
        isEnabled: (record["Disposition"] ?? "").contains("enabled"),
        url: url, parentIdentifier: parent)
    }
  }

  private static func resolve(
    _ raw: String, parent: String?, absolute: [String: URL]
  ) -> URL? {
    guard !raw.isEmpty else { return nil }
    if raw.hasPrefix("file://") {
      return URL(string: raw)?.standardizedFileURL
    }
    // Relative to the parent app's bundle. The database percent-encodes the
    // path, so decode before joining.
    guard let parent, let base = absolute[parent] else { return nil }
    let relative = raw.removingPercentEncoding ?? raw
    return base.appendingPathComponent(relative).standardizedFileURL
  }

  /// Items whose app no longer lives where it should — the ones still
  /// switched on in System Settings for software that is gone.
  public static func stale(in items: [BackgroundItem], trash: URL? = nil) -> [StaleBackgroundItem] {
    let trashPath = (trash ?? FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".Trash", isDirectory: true)).standardizedFileURL.path
    return items.compactMap { item in
      guard let url = item.url else { return nil }
      let exists = FileManager.default.fileExists(atPath: url.path)
      // Location alone does not decide it: after the Trash is emptied the
      // database still points into it, and calling that "in the Trash"
      // would send the user looking for something already gone.
      if url.path.hasPrefix(trashPath + "/") {
        return StaleBackgroundItem(item: item, reason: exists ? .appInTrash : .appMissing)
      }
      return exists ? nil : StaleBackgroundItem(item: item, reason: .appMissing)
    }
  }
}
