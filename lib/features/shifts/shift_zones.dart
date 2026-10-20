/// Wall clocks in an event's own zone, for the planner's editors (HIN-160).
///
/// The helper surfaces never convert: the server sends every time twice, as
/// an instant and as the wall clock in the event's zone. A planner typing
/// "14:00" into an event in another zone is the one case that needs the
/// opposite direction, and only there is the zone database loaded, on first
/// use and deferred, so no other screen pays for it.
library;

import 'package:timezone/data/latest_10y.dart' deferred as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/util/reader_time_zone.dart';

/// Turns a wall clock in a named zone into an instant and back.
class ShiftZones {
  ShiftZones._();

  static bool _loaded = false;
  static Future<void>? _loading;

  /// The device's zone, as far as the platform says.
  static Future<String?> deviceZone() => ReaderTimeZone.resolve();

  /// Loads the zone database once. Cheap after the first call.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      await tzdata.loadLibrary();
      tzdata.initializeTimeZones();
      _loaded = true;
    }();
  }

  /// Every zone id the database knows, sorted, for the zone picker.
  static List<String> all() {
    if (!_loaded) return const [];
    return tz.timeZoneDatabase.locations.keys.toList()..sort();
  }

  /// Whether [zone] is a zone the database knows; false before it is loaded.
  static bool known(String zone) =>
      _loaded && tz.timeZoneDatabase.locations.containsKey(zone);

  /// The instant at which the clocks in [zone] read [wall] (its date and time
  /// fields; whatever zone the [DateTime] itself is in is ignored).
  ///
  /// [deviceZone] or a null [zone] means the device's own clock, which needs no
  /// database. An unknown zone falls back to the device's clock too: the
  /// server corrects nothing, so a wrong guess would be stored, and the device
  /// is the nearest thing to what the planner sees.
  static DateTime toInstant(DateTime wall, String? zone, String? deviceZone) {
    if (zone == null || zone == deviceZone || !known(zone)) {
      return DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute);
    }
    final at = tz.TZDateTime(
      tz.getLocation(zone),
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    );
    return DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch);
  }

  /// What the clocks in [zone] read at [instant], as a naive [DateTime].
  static DateTime toWall(DateTime instant, String? zone, String? deviceZone) {
    if (zone == null || zone == deviceZone || !known(zone)) {
      final local = instant.toLocal();
      return DateTime(
        local.year,
        local.month,
        local.day,
        local.hour,
        local.minute,
      );
    }
    final at = tz.TZDateTime.from(instant, tz.getLocation(zone));
    return DateTime(at.year, at.month, at.day, at.hour, at.minute);
  }
}
