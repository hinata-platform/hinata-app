import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for app-level persistence.
/// Tokens are kept here too; on mobile SharedPreferences is sandboxed
/// per-app, and the refresh token is short-lived enough for this app class.
class AppStorage {
  AppStorage(this._prefs);

  static const _kServerUrl = 'server_url';
  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kOnboardingDone = 'onboarding_done';
  static const _kLocale = 'locale';

  final SharedPreferences _prefs;

  static Future<AppStorage> create() async =>
      AppStorage(await SharedPreferences.getInstance());

  String? get serverUrl => _prefs.getString(_kServerUrl);
  Future<void> setServerUrl(String url) => _prefs.setString(_kServerUrl, url);

  String? get accessToken => _prefs.getString(_kAccessToken);
  String? get refreshToken => _prefs.getString(_kRefreshToken);

  Future<void> setTokens({required String access, required String refresh}) async {
    await _prefs.setString(_kAccessToken, access);
    await _prefs.setString(_kRefreshToken, refresh);
  }

  Future<void> clearTokens() async {
    await _prefs.remove(_kAccessToken);
    await _prefs.remove(_kRefreshToken);
  }

  bool get onboardingDone => _prefs.getBool(_kOnboardingDone) ?? false;
  Future<void> setOnboardingDone() => _prefs.setBool(_kOnboardingDone, true);

  String? get locale => _prefs.getString(_kLocale);
  Future<void> setLocale(String code) => _prefs.setString(_kLocale, code);
}
