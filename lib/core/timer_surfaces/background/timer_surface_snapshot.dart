import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../timer_surface_prefs.dart';
import '../timer_surface_state.dart';

/// What a background isolate needs to redraw the surfaces after an action
/// (HIN-103): the person's switches and the words in their language.
///
/// Written by the running app whenever it draws, removed when it is signed
/// out. No timer, no description, no id: the isolate asks the server for the
/// timer itself.
class TimerSurfaceSnapshot {
  const TimerSurfaceSnapshot({required this.prefs, required this.texts});

  static const String key = 'timer_surface_snapshot.v1';

  final TimerSurfacePrefs prefs;
  final TimerSurfaceTexts texts;

  String encode() =>
      jsonEncode({'prefs': prefs.toJson(), 'texts': texts.toJson()});

  /// Null for anything that does not read as one.
  static TimerSurfaceSnapshot? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return TimerSurfaceSnapshot(
        prefs: TimerSurfacePrefs.fromJson(
          json['prefs'] as Map<String, dynamic>,
        ),
        texts: TimerSurfaceTexts.fromJson(
          json['texts'] as Map<String, dynamic>,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Where [TimerSurfaceSnapshot] lives: the app's own preferences.
class TimerSurfaceSnapshotStore {
  const TimerSurfaceSnapshotStore();

  Future<TimerSurfaceSnapshot?> read() async {
    final prefs = await SharedPreferences.getInstance();
    // Another isolate wrote it; the cache of this one may predate that.
    await prefs.reload();
    return TimerSurfaceSnapshot.decode(
      prefs.getString(TimerSurfaceSnapshot.key),
    );
  }

  Future<void> write(TimerSurfaceSnapshot? snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    if (snapshot == null) {
      await prefs.remove(TimerSurfaceSnapshot.key);
    } else {
      await prefs.setString(TimerSurfaceSnapshot.key, snapshot.encode());
    }
  }
}
