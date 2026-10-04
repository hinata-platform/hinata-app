import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/account_models.dart';
import '../../core/models/personal_access_token.dart';
import '../../core/repositories/account_repository.dart';

/// The reader's own account (`/me`): the settings page, its profile, e-mail,
/// two-factor and deletion modals, the token section, and the shell's avatar
/// menu, which edits the profile without a detour through the settings.
///
/// Holds no state of its own. Each surface keeps what it shows where it kept
/// it, and every call answers or fails exactly as the repository does.
class AccountCubit extends Cubit<void> {
  AccountCubit(this._account) : super(null);

  final AccountRepository _account;

  Future<Me> me() => _account.meAccount();

  Future<Me> updateProfile({
    String? displayName,
    String? title,
    String? pronouns,
    String? locale,
    String? timezone,
    TimePreferences? timePreferences,
  }) => _account.updateMyProfile(
    displayName: displayName,
    title: title,
    pronouns: pronouns,
    locale: locale,
    timezone: timezone,
    timePreferences: timePreferences,
  );

  Future<String> uploadAvatar(
    MultipartFile file, {
    void Function(double pct)? onProgress,
  }) => _account.uploadAvatar(file, onProgress: onProgress);

  Future<void> deleteAvatar() => _account.deleteAvatar();

  Future<void> requestEmailChange(String newEmail) =>
      _account.requestEmailChange(newEmail);

  Future<void> sendPasswordReset() => _account.sendPasswordReset();

  Future<({List<DeviceSession> items, int total})> sessionsPage({
    int page = 0,
    int size = 25,
  }) => _account.sessionsPage(page: page, size: size);

  Future<void> revokeSession(String id) => _account.revokeSession(id);

  Future<void> revokeOtherSessions() => _account.revokeOtherSessions();

  Future<NotifPrefs> saveNotificationPrefs(NotifPrefs prefs) =>
      _account.saveNotificationPrefs(prefs);

  Future<TotpSetup> beginTotpSetup() => _account.beginTotpSetup();

  Future<List<String>> verifyTotpSetup(String code) =>
      _account.verifyTotpSetup(code);

  Future<List<String>> regenerateRecoveryCodes(String code) =>
      _account.regenerateRecoveryCodes(code);

  Future<void> disableTotp(String code) => _account.disableTotp(code);

  Future<List<AccessTeam>> myTeams() => _account.myTeams();

  Future<List<AccessProject>> myProjects() => _account.myProjects();

  Future<void> requestDataReport() => _account.requestDataReport();

  Future<void> deleteAccount() => _account.deleteMyAccount();

  Future<List<PersonalAccessToken>> pats() => _account.listPats();

  Future<CreatedPat> createPat({
    required String name,
    required List<String> scopes,
    int? ttlDays,
  }) => _account.createPat(name: name, scopes: scopes, ttlDays: ttlDays);

  Future<void> revokePat(String id) => _account.revokePat(id);

  Future<void> deletePat(String id) => _account.deletePat(id);
}
