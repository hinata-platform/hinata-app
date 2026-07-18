import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_profile.dart';

/// Thin wrapper around SharedPreferences for app-level persistence.
///
/// The app can hold several saved servers and switch between them. The
/// currently selected server lives under [_kServerUrl]; the full list lives
/// under [_kServers]. Auth tokens are kept here too and are **scoped per
/// server** (keyed by URL) so the token issued by one backend is never sent to
/// another. On mobile SharedPreferences is sandboxed per-app, and the refresh
/// token is short-lived enough for this app class.
class AppStorage {
  AppStorage(this._prefs);

  static const _kServerUrl = 'server_url';
  static const _kServers = 'servers.v1';
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kConnectHintSeen = 'connect_hint_seen';
  static const _kLocale = 'locale';
  static const _kRecentSearch = 'hinata.recentSearch.v1';

  /// Maximum number of recent global-search queries kept on device.
  static const recentSearchMax = 6;

  final SharedPreferences _prefs;

  static Future<AppStorage> create() async {
    final storage = AppStorage(await SharedPreferences.getInstance());
    await storage._migrateToMultiServer();
    return storage;
  }

  // --- current server --------------------------------------------------------

  /// The URL of the server the app is currently talking to (null on first run).
  String? get serverUrl => _prefs.getString(_kServerUrl);

  /// Selects [url] as the current server (adding it to the saved list if new).
  /// Kept as the historical setter name so existing callers (connect flow,
  /// deep-link handoff) transparently register the server too.
  Future<void> setServerUrl(String url) => setCurrentServer(url);

  Future<void> setCurrentServer(String url) async {
    await upsertServer(ServerProfile(url: url));
    await _prefs.setString(_kServerUrl, url);
  }

  // --- saved servers ---------------------------------------------------------

  /// All servers the user has connected to, in insertion order.
  List<ServerProfile> get servers {
    final raw = _prefs.getString(_kServers);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Adds [profile], or refreshes the label of an already-saved server. A null
  /// or blank incoming label never clobbers a previously stored one.
  Future<void> upsertServer(ServerProfile profile) async {
    final list = servers.toList();
    final i = list.indexWhere((s) => s.url == profile.url);
    if (i >= 0) {
      final keepLabel = (profile.label?.trim().isNotEmpty ?? false)
          ? profile.label
          : list[i].label;
      list[i] = ServerProfile(url: profile.url, label: keepLabel);
    } else {
      list.add(profile);
    }
    await _saveServers(list);
  }

  /// Forgets a server: drops it from the list and wipes its scoped tokens. If it
  /// was the current server, the current selection is cleared (the caller then
  /// switches elsewhere or routes back to the connect screen).
  Future<void> removeServer(String url) async {
    await _saveServers(servers.where((s) => s.url != url).toList());
    await _prefs.remove(_accessKey(url));
    await _prefs.remove(_refreshKey(url));
    if (serverUrl == url) await _prefs.remove(_kServerUrl);
  }

  Future<void> _saveServers(List<ServerProfile> list) => _prefs.setString(
        _kServers,
        jsonEncode(list.map((s) => s.toJson()).toList()),
      );

  // --- tokens (scoped to the current server) ---------------------------------

  String _accessKey(String url) => '$_kAccessToken::$url';
  String _refreshKey(String url) => '$_kRefreshToken::$url';

  String? get accessToken {
    final url = serverUrl;
    return url == null ? null : _prefs.getString(_accessKey(url));
  }

  String? get refreshToken {
    final url = serverUrl;
    return url == null ? null : _prefs.getString(_refreshKey(url));
  }

  Future<void> setTokens({required String access, required String refresh}) async {
    final url = serverUrl;
    if (url == null) return;
    await _prefs.setString(_accessKey(url), access);
    await _prefs.setString(_refreshKey(url), refresh);
  }

  Future<void> clearTokens() async {
    final url = serverUrl;
    if (url == null) return;
    await _prefs.remove(_accessKey(url));
    await _prefs.remove(_refreshKey(url));
  }

  /// One-time upgrade from the single-server layout (a lone `server_url` plus
  /// global `access_token`/`refresh_token`) to the multi-server layout: seed the
  /// server list from the existing URL and move its tokens into the per-server
  /// keys. Runs once — the presence of [_kServers] marks it done.
  Future<void> _migrateToMultiServer() async {
    if (_prefs.containsKey(_kServers)) return;
    final url = _prefs.getString(_kServerUrl);
    final list = <ServerProfile>[];
    if (url != null && url.isNotEmpty) {
      list.add(ServerProfile(url: url));
      final access = _prefs.getString(_kAccessToken);
      final refresh = _prefs.getString(_kRefreshToken);
      if (access != null) await _prefs.setString(_accessKey(url), access);
      if (refresh != null) await _prefs.setString(_refreshKey(url), refresh);
    }
    await _prefs.remove(_kAccessToken);
    await _prefs.remove(_kRefreshToken);
    await _saveServers(list);
  }

  // --- misc ------------------------------------------------------------------

  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone() => _prefs.setBool(_kOnboardingDone, true);

  // --- Hinata Connect first-login hint (scoped per server) -------------------

  String _connectHintKey(String url) => '$_kConnectHintSeen::$url';

  /// Whether the "get a Connect licence" hint has already been shown for the
  /// current server. Scoped per instance — each self-hosted server an admin
  /// connects to is prompted once. Returns true (suppressed) when no server is
  /// selected yet.
  bool get connectHintSeen {
    final url = serverUrl;
    return url == null ? true : (_prefs.getBool(_connectHintKey(url)) ?? false);
  }

  Future<void> setConnectHintSeen() async {
    final url = serverUrl;
    if (url == null) return;
    await _prefs.setBool(_connectHintKey(url), true);
  }

  String? get locale => _prefs.getString(_kLocale);
  Future<void> setLocale(String code) => _prefs.setString(_kLocale, code);

  /// Tooling-only: lets the screenshot harness force the boot route via a
  /// pre-seeded pref (no effect in normal use, where the key is absent).
  String? get screenshotRoute => _prefs.getString('screenshot_route');

  /// Recent global-search queries, most-recent first (max [recentSearchMax]).
  List<String> get recentSearches =>
      _prefs.getStringList(_kRecentSearch) ?? const [];

  Future<void> setRecentSearches(List<String> list) =>
      _prefs.setStringList(
          _kRecentSearch, list.take(recentSearchMax).toList());
}
