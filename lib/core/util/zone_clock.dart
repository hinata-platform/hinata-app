/// What the clocks in another time zone read, for a person's profile.
///
/// The zone database is large, so it is loaded deferred and only on first use;
/// a reader who never opens a colleague's profile never pays for it.
library;

import 'package:timezone/data/latest_10y.dart' deferred as tzdata;
import 'package:timezone/timezone.dart' as tz;

class ZoneClock {
  ZoneClock._();

  static bool _loaded = false;
  static Future<void>? _loading;

  /// Loads the zone database once. Cheap after the first call; a database
  /// that will not load leaves [wallClock] answering null.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      try {
        await tzdata.loadLibrary();
        tzdata.initializeTimeZones();
        _loaded = true;
      } catch (_) {
        // A build without the deferred part: no other zones, no harm done.
      }
    }();
  }

  /// The wall clock in [zone] at [instant], as a naive [DateTime]; null for a
  /// zone the database does not know or before it is loaded.
  static DateTime? wallClock(String zone, DateTime instant) {
    if (!_loaded || !tz.timeZoneDatabase.locations.containsKey(zone)) {
      return null;
    }
    final at = tz.TZDateTime.from(instant, tz.getLocation(zone));
    return DateTime(at.year, at.month, at.day, at.hour, at.minute);
  }
}
