import XCTest

@testable import Runner

/// The sealed Live Activity state (HIN-103), against the vector the server
/// test seals the same way (`LiveActivityContentTest` in hinata-server): key
/// bytes 0…31, nonce bytes 0…11, associated data `hinata-la-v1:vector-activity`.
@available(iOS 16.1, *)
final class TimerActivityCryptoTests: XCTestCase {
  private let key = Data((0..<32).map { UInt8($0) })
  private let nonce = "AAECAwQFBgcICQoL"
  private let cipher =
    "PCC7dKGA4CGvIvj+350cAvS4pRjSCzcdSwLHv3McbN4tMs2FzK136zDLEYiqvRgUzCoU7Ciixr5+4wgjKdTM38cF9Erj4RZRLHiIC4HrfalMqPNTQVpiX8TPqPxIwIm959o9j9csoWntXUqQckQWRotQW53R9RWqfc977+eICmvfcDqg1bu4NnUH+gPLNTHjDJ1OApcvwhH3"

  func testTheServersVectorOpensToItsPlaintext() {
    let plain = TimerActivityCrypto.open(n: nonce, c: cipher, key: key, ref: "vector-activity")

    XCTAssertEqual(
      plain,
      TimerActivityCrypto.Plain(
        mode: "countdown", phase: nil, cyclesDone: 0, startedAt: 1_791_792_000_000,
        endsAt: 1_791_792_600_000, dismissAt: 1_791_796_200_000, ended: false))
  }

  func testAWrongKeyOrAnotherActivityOpensNothing() {
    XCTAssertNil(
      TimerActivityCrypto.open(
        n: nonce, c: cipher, key: TimerActivityCrypto.newKey(), ref: "vector-activity"))
    XCTAssertNil(TimerActivityCrypto.open(n: nonce, c: cipher, key: key, ref: "other-activity"))
  }

  func testASealedStateDecodesAndDrawsWithTheWordsOfThePhone() throws {
    let json = Data(#"{"v":1,"n":"\#(nonce)","c":"\#(cipher)"}"#.utf8)
    let state = try JSONDecoder().decode(TimerActivityAttributes.ContentState.self, from: json)
    let record = TimerActivityRecord(
      key: key,
      words: ["running": "Timer läuft", "countdownOver": "Countdown vorbei"],
      label: nil)

    let drawn = state.resolved(ref: "vector-activity", record: record)

    XCTAssertFalse(drawn.hidesTime)
    XCTAssertEqual(drawn.title, "Timer läuft")
    XCTAssertEqual(drawn.staleTitle, "Countdown vorbei")
    XCTAssertEqual(drawn.endsAt, Date(timeIntervalSince1970: 1_791_792_600))
    XCTAssertEqual(drawn.dismissAt, Date(timeIntervalSince1970: 1_791_792_600 + 3600))
  }

  func testAStateThePhoneCannotOpenDrawsTimerWithoutTimes() throws {
    let json = Data(#"{"v":1,"n":"\#(nonce)","c":"\#(cipher)"}"#.utf8)
    let state = try JSONDecoder().decode(TimerActivityAttributes.ContentState.self, from: json)
    let wrong = TimerActivityRecord(key: TimerActivityCrypto.newKey(), words: [:], label: nil)

    let drawn = state.resolved(ref: "vector-activity", record: wrong)

    XCTAssertTrue(drawn.hidesTime)
    XCTAssertEqual(drawn.title, String(localized: "widget.name"))
  }

  func testTheAppsOwnStateSurvivesTheRoundTrip() throws {
    let state = TimerActivityAttributes.ContentState(
      mode: "pomodoro", phase: "work", startedAt: Date(timeIntervalSince1970: 100),
      endsAt: Date(timeIntervalSince1970: 1600), dismissAt: Date(timeIntervalSince1970: 5200),
      title: "Fokus", staleTitle: "Pause?", label: nil)

    let decoded = try JSONDecoder().decode(
      TimerActivityAttributes.ContentState.self, from: JSONEncoder().encode(state))

    XCTAssertEqual(decoded, state)
    XCTAssertNil(decoded.sealed)
  }
}
