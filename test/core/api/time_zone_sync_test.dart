import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/api/time_zone_sync.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';

/// The whole point of this sync is what it does *not* do. It runs on every
/// sign-in and every return to the foreground, so a rule that is one condition
/// too loose turns a convenience into a write on every app switch — against the
/// account of whoever happens to be signed in.
void main() {
  group('shouldSyncTimeZone', () {
    test('sends a zone the account does not have yet', () {
      expect(
        shouldSyncTimeZone(deviceZone: 'Europe/Berlin', accountZone: null),
        isTrue,
      );
    });

    test('sends a zone that changed', () {
      expect(
        shouldSyncTimeZone(
          deviceZone: 'Asia/Tokyo',
          accountZone: 'Europe/Berlin',
        ),
        isTrue,
      );
    });

    test('stays quiet when the two already agree', () {
      expect(
        shouldSyncTimeZone(
          deviceZone: 'Europe/Berlin',
          accountZone: 'Europe/Berlin',
        ),
        isFalse,
      );
    });

    test('never overwrites a configured zone with nothing', () {
      // The platform declining to name a zone is an ordinary answer: the server
      // then falls back to the organization's own setting, which an admin chose.
      expect(
        shouldSyncTimeZone(deviceZone: null, accountZone: 'Europe/Berlin'),
        isFalse,
      );
      expect(shouldSyncTimeZone(deviceZone: null, accountZone: null), isFalse);
      expect(
        shouldSyncTimeZone(deviceZone: '', accountZone: 'Europe/Berlin'),
        isFalse,
      );
    });
  });

  group('TimeZoneSync', () {
    test('writes once on a difference and never again', () async {
      final account = _FakeAccountRepository(zone: 'Europe/Berlin');
      final sync = TimeZoneSync(
        account: account,
        deviceZone: () async => 'Asia/Tokyo',
      );

      await sync.sync();
      expect(account.patched, ['Asia/Tokyo']);
      expect(account.reads, 1);

      // A resume, and another: the account is known to agree now, so neither
      // costs a request at all.
      await sync.sync();
      await sync.sync();
      expect(account.patched, ['Asia/Tokyo']);
      expect(account.reads, 1);
    });

    test('writes nothing when the account already carries the zone', () async {
      final account = _FakeAccountRepository(zone: 'Europe/Berlin');
      final sync = TimeZoneSync(
        account: account,
        deviceZone: () async => 'Europe/Berlin',
      );

      await sync.sync();
      await sync.sync();

      expect(account.patched, isEmpty);
      expect(account.reads, 1);
    });

    test('writes nothing when the platform will not name a zone', () async {
      final account = _FakeAccountRepository(zone: null);
      final sync = TimeZoneSync(account: account, deviceZone: () async => null);

      await sync.sync();

      expect(account.patched, isEmpty);
      expect(account.reads, 0, reason: 'nothing to compare, so nothing to ask');
    });

    test('a failed write is retried, and stays silent', () async {
      final account = _FakeAccountRepository(zone: null, failPatch: true);
      final sync = TimeZoneSync(
        account: account,
        deviceZone: () async => 'Asia/Tokyo',
      );

      await sync.sync();
      expect(account.patched, ['Asia/Tokyo']);

      // The next resume tries again — without re-reading the account, which it
      // already knows — and the failure never surfaced anywhere.
      await sync.sync();
      expect(account.patched, ['Asia/Tokyo', 'Asia/Tokyo']);
      expect(account.reads, 1);
    });

    test('a failed read is asked again rather than assumed', () async {
      final account = _FakeAccountRepository(
        zone: 'Asia/Tokyo',
        failRead: true,
      );
      final sync = TimeZoneSync(
        account: account,
        deviceZone: () async => 'Asia/Tokyo',
      );

      await sync.sync();
      expect(account.reads, 1);
      expect(account.patched, isEmpty);

      account.failRead = false;
      await sync.sync();
      expect(account.reads, 2);
      // The server turned out to have the same zone all along: still no write.
      expect(account.patched, isEmpty);
    });

    test('signing out forgets the previous account', () async {
      final account = _FakeAccountRepository(zone: 'Asia/Tokyo');
      final sync = TimeZoneSync(
        account: account,
        deviceZone: () async => 'Asia/Tokyo',
      );

      await sync.sync();
      expect(account.reads, 1);

      sync.reset();
      account.zone = null; // a different person signs in on this device
      await sync.sync();

      expect(account.reads, 2);
      expect(account.patched, ['Asia/Tokyo']);
    });

    test(
      'a server that does not echo the field back is still written once',
      () async {
        // Every self-hosted server older than this field answers a PATCH without
        // a timezone. Believing that answer would mean the two never agree, and
        // every single foregrounding of the app would send another write.
        final account = _FakeAccountRepository(
          zone: null,
          echoesTimezone: false,
        );
        final sync = TimeZoneSync(
          account: account,
          deviceZone: () async => 'Asia/Tokyo',
        );

        await sync.sync();
        await sync.sync();
        await sync.sync();

        expect(account.patched, ['Asia/Tokyo']);
        expect(account.reads, 1);
      },
    );

    test('a zone the server refuses is offered once, not forever', () async {
      // A device on a newer tz database than the server's — "Europe/Kyiv"
      // against a JDK that only knows "Europe/Kiev". The app cannot tell in
      // advance; what it must not do is ask again on every resume.
      final account = _FakeAccountRepository(zone: null, refusePatch: true);
      final sync = TimeZoneSync(
        account: account,
        deviceZone: () async => 'Europe/Kyiv',
      );

      await sync.sync();
      await sync.sync();
      await sync.sync();

      expect(account.patched, ['Europe/Kyiv']);
    });

    test(
      'a 400 from the read does not latch a zone that was never sent',
      () async {
        // The latch is about a zone the server refused. A read that fails with
        // the same status said nothing about the zone, and treating it as a
        // refusal would switch the sync off for the rest of the process.
        final account = _FakeAccountRepository(zone: null, readStatus: 400);
        final sync = TimeZoneSync(
          account: account,
          deviceZone: () async => 'Europe/Berlin',
        );

        await sync.sync();
        expect(account.patched, isEmpty);

        account.readStatus = null;
        await sync.sync();

        expect(account.patched, ['Europe/Berlin']);
      },
    );

    test('a refusal for one account does not silence the next', () async {
      // The latch is set from the value already in hand. Reading the platform
      // again inside the catch would let a sign-out land in between, and the
      // refusal would then outlive the account it was about — the next person
      // on this device would never be stamped at all.
      final account = _FakeAccountRepository(zone: null, refusePatch: true);
      final sync = TimeZoneSync(
        account: account,
        deviceZone: () async => 'Europe/Kyiv',
      );

      await sync.sync();
      expect(account.patched, ['Europe/Kyiv']);

      sync.reset();
      account.refusePatch = false;
      await sync.sync();

      expect(account.patched, [
        'Europe/Kyiv',
        'Europe/Kyiv',
      ], reason: 'the new account is offered the zone again');
    });

    test(
      'an answer that lands after sign-out is not written onto the next account',
      () async {
        // The read is in flight when the user signs out. Its answer describes the
        // account that has gone; comparing the next one against it would leave
        // the new account never stamped at all.
        final account = _FakeAccountRepository(zone: 'Europe/Berlin');
        final sync = TimeZoneSync(
          account: account,
          deviceZone: () async => 'Europe/Berlin',
        );
        account.onRead = sync.reset;

        await sync.sync();

        // The stale answer was dropped, so the next run reads again — and this
        // time writes, because the new account has no zone.
        account.onRead = null;
        account.zone = null;
        await sync.sync();

        expect(account.reads, 2);
        expect(account.patched, ['Europe/Berlin']);
      },
    );
  });
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({
    required this.zone,
    this.failRead = false,
    this.failPatch = false,
    this.refusePatch = false,
    this.echoesTimezone = true,
    this.readStatus,
  });

  String? zone;
  bool failRead;
  bool failPatch;

  /// Answers a write with 400, the way a server that cannot parse the zone does.
  bool refusePatch;

  /// Status a *read* fails with, when it should fail at all.
  int? readStatus;

  /// Whether the PATCH answer carries the field at all — a server older than
  /// this feature does not.
  bool echoesTimezone;

  /// Runs while a read is "in flight", so a sign-out can land mid-await.
  void Function()? onRead;

  int reads = 0;
  final List<String?> patched = [];

  @override
  Future<Me> meAccount() async {
    reads++;
    if (readStatus != null) {
      throw ApiFailure('errors.unexpected', statusCode: readStatus);
    }
    if (failRead) throw ApiFailure('errors.network');
    onRead?.call();
    return _me(zone);
  }

  @override
  Future<Me> updateMyProfile({
    String? displayName,
    String? title,
    String? pronouns,
    String? locale,
    String? timezone,
  }) async {
    patched.add(timezone);
    if (refusePatch) {
      throw ApiFailure('error.user.invalidTimezone', statusCode: 400);
    }
    if (failPatch) throw ApiFailure('errors.unexpected');
    zone = timezone;
    return _me(echoesTimezone ? timezone : null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

Me _me(String? timezone) => Me(
  id: 'me',
  displayName: 'Me',
  username: 'me',
  email: 'me@example.test',
  emailVerified: true,
  origin: AuthOrigin.local,
  roles: const ['USER'],
  active: true,
  twoFactor: const TwoFactor(enabled: false),
  notificationPreferences: const NotifPrefs(
    emailEnabled: true,
    pushEnabled: true,
    events: {},
  ),
  timezone: timezone,
);
