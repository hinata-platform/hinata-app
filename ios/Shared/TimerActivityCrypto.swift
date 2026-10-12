import CryptoKit
import Foundation

/// Opens the sealed state the server sends to a Live Activity (HIN-103).
///
/// The wire form is `{"v":1,"n":<nonce>,"c":<ciphertext+tag>}`, both standard
/// Base64: AES-256-GCM with a 96-bit nonce and a 128-bit tag, the activity's
/// reference as associated data (`hinata-la-v1:<ref>`), so a state made for
/// one activity does not open in another. The plaintext carries the timer's
/// shape only: mode, phase, cycles, start, end of the stretch, ended.
enum TimerActivityCrypto {
  static let version = 1

  struct Plain: Decodable, Equatable {
    var mode: String
    var phase: String?
    var cyclesDone: Int?
    var startedAt: Double?
    var endsAt: Double?
    var ended: Bool
  }

  /// A fresh 256-bit key for a new activity.
  static func newKey() -> Data {
    SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
  }

  static func open(n: String, c: String, key: Data, ref: String) -> Plain? {
    guard let nonceData = Data(base64Encoded: n),
      let sealed = Data(base64Encoded: c),
      sealed.count > 16,
      let nonce = try? AES.GCM.Nonce(data: nonceData),
      let box = try? AES.GCM.SealedBox(
        nonce: nonce, ciphertext: sealed.dropLast(16), tag: sealed.suffix(16)),
      let plain = try? AES.GCM.open(
        box, using: SymmetricKey(data: key), authenticating: Data("hinata-la-v1:\(ref)".utf8))
    else { return nil }
    return try? JSONDecoder().decode(Plain.self, from: plain)
  }
}

#if canImport(ActivityKit)
  @available(iOS 16.1, *)
  extension TimerActivityAttributes.ContentState {
    /// What this state draws for the activity [ref]: itself when the app wrote
    /// it, the opened state when the server sent it, and "Timer" without any
    /// time when it cannot be opened (no key on this phone, a wrong key).
    func resolved(ref: String, record: TimerActivityRecord? = nil) -> Self {
      guard let sealed else { return self }
      let words = (record ?? TimerActivityKeychain.load(ref: ref))
      guard sealed.v == TimerActivityCrypto.version, let words,
        let plain = TimerActivityCrypto.open(n: sealed.n, c: sealed.c, key: words.key, ref: ref),
        !plain.ended, let started = plain.startedAt
      else { return .opaque }
      let startedAt = Date(timeIntervalSince1970: started / 1000)
      let endsAt = plain.endsAt.map { Date(timeIntervalSince1970: $0 / 1000) }
      let byDay = startedAt.addingTimeInterval(24 * 3600)
      let dismissAt = endsAt.map { min($0.addingTimeInterval(3600), byDay) } ?? byDay
      let isBreak = plain.phase == "shortBreak" || plain.phase == "longBreak"
      let staleTitle: String? =
        endsAt == nil
        ? nil
        : plain.mode == "countdown"
          ? words.words["countdownOver"] : words.words[isBreak ? "breakOver" : "workOver"]
      return Self(
        mode: plain.mode,
        phase: plain.phase,
        startedAt: startedAt,
        endsAt: endsAt,
        dismissAt: dismissAt,
        title: words.words[isBreak ? "onBreak" : "running"] ?? "",
        staleTitle: staleTitle,
        label: words.label
      )
    }
  }
#endif
