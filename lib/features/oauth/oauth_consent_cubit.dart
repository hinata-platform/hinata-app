import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/oauth_consent.dart';
import '../../core/repositories/auth_repository.dart';

/// The OAuth consent page: the pending request an AI client started, and the
/// reader's decision on it.
///
/// Holds no state of its own: the page keeps its loading and deciding flags
/// and sends the browser on to the redirect it gets back.
class OAuthConsentCubit extends Cubit<void> {
  OAuthConsentCubit(this._auth) : super(null);

  final AuthRepository _auth;

  Future<OAuthConsentInfo> info(String requestId) =>
      _auth.oauthConsentInfo(requestId);

  /// Records the decision and answers the `redirectUri` the browser goes to.
  Future<String> decide(
    String requestId, {
    required bool approved,
    required List<String> grantedScopes,
  }) => _auth.oauthConsentDecision(
    requestId,
    approved: approved,
    grantedScopes: grantedScopes,
  );
}
