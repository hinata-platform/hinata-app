import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../repositories/account_repository.dart';
import '../util/reader_time_zone.dart';
import 'api_client.dart';

/// Whether the device's zone is worth writing to the account.
///
/// Top-level and public so the rule can be tested without a server: the cases
/// it must *not* fire on carry the whole weight of this feature. A platform
/// that will not name its zone ([ReaderTimeZone.resolve] answering null) is an
/// ordinary answer, not a reason to overwrite what an admin or another device
/// configured; and a zone that already matches must not be re-sent, or every
/// foregrounding of the app would be a write.
bool shouldSyncTimeZone({
  required String? deviceZone,
  required String? accountZone,
}) => deviceZone != null && deviceZone.isNotEmpty && deviceZone != accountZone;

/// Keeps `User.timezone` in step with the zone the device is set to.
///
/// The server needs it for the things it decides without the reader in front
/// of it: whether a logged date is "in the future", and what a rendered PDF
/// stamps its times in. The process runs with its clock pinned to UTC and an
/// HTTP request says which language the reader wants but never where they are —
/// so the app is the only one who can say, and it says it once.
///
/// Driven from the auth lifecycle: [sync] after sign-in and on app resume,
/// [reset] on sign-out so the next account is never compared against the
/// previous one's zone. It is deliberately quiet — a zone that could not be
/// read, a `/me` that did not answer, a rejected PATCH: none of them is worth a
/// message to a reader who never asked for this, and every one of them is
/// retried on the next resume at no cost.
class TimeZoneSync {
  TimeZoneSync({
    required AccountRepository account,
    Future<String?> Function()? deviceZone,
  }) : _account = account,
       _deviceZone = deviceZone ?? ReaderTimeZone.resolve;

  final AccountRepository _account;

  /// How the device is asked for its zone. Injectable so the rules above can be
  /// exercised without a platform channel; production passes nothing.
  final Future<String?> Function() _deviceZone;

  /// What this account's zone is as far as we know, remembered for the life of
  /// the process. Once it agrees with the device, a resume costs nothing at all
  /// — no request, not even a read.
  String? _accountZone;
  bool _known = false;

  /// A zone the server refused. Kept so a device the server cannot parse — an
  /// id from a tz database newer than the one its JDK ships, say — is asked
  /// about once rather than on every foregrounding for the life of the install.
  String? _refused;

  /// One run at a time, so a resume that lands while sign-in's run is still
  /// in flight cannot send the same PATCH twice.
  bool _running = false;

  /// Bumped by [reset]. An answer that arrives after a sign-out belongs to the
  /// account that has gone, and must not be written onto the one that follows.
  int _generation = 0;

  Future<void> sync() async {
    if (_running) return;
    _running = true;
    final generation = _generation;
    try {
      final device = await _deviceZone();
      if (device == null || device == _refused) return;
      // Already reconciled in this process: nothing changed on our side, so
      // there is nothing to ask the server about.
      if (_known &&
          !shouldSyncTimeZone(deviceZone: device, accountZone: _accountZone)) {
        return;
      }
      if (!_known) {
        final zone = (await _account.meAccount()).timezone;
        if (generation != _generation) return;
        _accountZone = zone;
        _known = true;
      }
      if (!shouldSyncTimeZone(deviceZone: device, accountZone: _accountZone)) {
        return;
      }
      await _account.updateMyProfile(timezone: device);
      if (generation != _generation) return;
      // What was sent, not what came back. A server older than this field
      // answers without it, and believing that answer would leave the two
      // disagreeing forever — one PATCH per foregrounding, for good. The write
      // was accepted; that is the fact worth remembering.
      _accountZone = device;
    } on ApiFailure catch (failure) {
      if (failure.statusCode == 400 && generation == _generation) {
        // The server has answered, and its answer is no. Asking again with the
        // same value would only ever get the same no.
        _refused = await _deviceZone();
      }
      if (kDebugMode) debugPrint('[timezone] not synced: $failure');
    } catch (error) {
      // Broad on purpose: a transport oddity or an unexpected body shape must
      // not take down a sign-in, and the retry is free. `_known` is only set
      // once the server has actually answered, so a failed read is asked again
      // rather than remembered as "matching".
      if (kDebugMode) debugPrint('[timezone] not synced: $error');
    } finally {
      _running = false;
    }
  }

  /// Forgets what the server said. Called on sign-out.
  void reset() {
    _generation++;
    _known = false;
    _accountZone = null;
    _refused = null;
  }
}
