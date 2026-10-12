import Foundation
import Security

/// What the phone keeps for one Live Activity that takes server updates
/// (HIN-103): the key its state is sealed with, the words it draws in the
/// reader's language, and the description if the person allows it on the lock
/// screen. The server sends times and nothing to read; these fill the rest.
///
/// Kept in the Keychain in a group shared by the Runner (which makes the key
/// and registers it) and the widget extension (which opens each state), with
/// `AfterFirstUnlockThisDeviceOnly`: readable on a locked phone once it has
/// been unlocked since boot, never in a backup, never on another device.
/// Deleted with the end of the activity.
struct TimerActivityRecord: Codable, Equatable {
  var key: Data
  var words: [String: String]
  var label: String?
}

enum TimerActivityKeychain {
  private static let service = "com.ahmadre.hinata.liveactivity"

  /// `$(AppIdentifierPrefix)com.ahmadre.hinata.shared`, from the Info.plist of
  /// the running target. Listed after the app's own group in the Runner's
  /// `keychain-access-groups`, so the auth tokens of flutter_secure_storage
  /// stay in the group they always were in.
  static var accessGroup: String? {
    Bundle.main.object(forInfoDictionaryKey: "HinataSharedKeychainGroup") as? String
  }

  private static func query(ref: String?) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
    ]
    if let ref { query[kSecAttrAccount as String] = ref }
    if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }
    return query
  }

  @discardableResult
  static func save(_ record: TimerActivityRecord, ref: String) -> Bool {
    guard let data = try? JSONEncoder().encode(record) else { return false }
    let base = query(ref: ref)
    let update: [String: Any] = [kSecValueData as String: data]
    if SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecSuccess { return true }
    var add = base
    add[kSecValueData as String] = data
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
  }

  static func load(ref: String) -> TimerActivityRecord? {
    var query = query(ref: ref)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return try? JSONDecoder().decode(TimerActivityRecord.self, from: data)
  }

  static func delete(ref: String) {
    SecItemDelete(query(ref: ref) as CFDictionary)
  }

  /// Every record of ours, also of activities an earlier run left behind.
  static func deleteAll() {
    SecItemDelete(query(ref: nil) as CFDictionary)
  }
}
