import Foundation

/// What the phone keeps for one Live Activity that takes server updates
/// (HIN-103): the key its state is sealed with, the words it draws in the
/// reader's language, and the description if the person allows it on the lock
/// screen. The server sends times and nothing to read; these fill the rest.
struct TimerActivityRecord: Codable, Equatable {
  var key: Data
  var words: [String: String]
  var label: String?
}

/// Where [TimerActivityRecord]s live: one file per activity in the App Group
/// container that only the Runner and the widget extension share.
///
/// Not the Keychain. A Live Activity is drawn in a context without one: on an
/// iPhone the extension's `SecItemCopyMatching` answers `errSecNotAvailable`
/// (-25291) there, so a key kept in a shared Keychain group can be written by
/// the app and never read where it is needed. The files are protected until
/// the first unlock after a restart (the same class the Keychain item would
/// have had), excluded from backups, so they stay on this device, and deleted
/// with the end of the activity.
enum TimerActivityStore {
  static let appGroup = "group.com.ahmadre.hinata"

  private static var folder: URL? {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroup)
    else { return nil }
    var url = container.appendingPathComponent("LiveActivities", isDirectory: true)
    if !FileManager.default.fileExists(atPath: url.path) {
      try? FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
    }
    return url
  }

  /// The file of [ref]; nil for anything that is not one of our references.
  private static func file(_ ref: String) -> URL? {
    guard UUID(uuidString: ref) != nil else { return nil }
    return folder?.appendingPathComponent("\(ref).json")
  }

  @discardableResult
  static func save(_ record: TimerActivityRecord, ref: String) -> Bool {
    guard let url = file(ref), let data = try? JSONEncoder().encode(record) else { return false }
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      return true
    } catch {
      return false
    }
  }

  static func load(ref: String) -> TimerActivityRecord? {
    guard let url = file(ref), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(TimerActivityRecord.self, from: data)
  }

  static func delete(ref: String) {
    guard let url = file(ref) else { return }
    try? FileManager.default.removeItem(at: url)
  }

  /// Every record of ours, also of activities an earlier run left behind.
  static func deleteAll() {
    guard let folder else { return }
    for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
