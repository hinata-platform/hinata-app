/// What an SSO sign-in that did not end in the app may say on the sign-in
/// screen.
///
/// The reason arrives in an address (`/login?ssoError=…` on the web,
/// `hinata://auth-callback?error=…` natively), and any web page can link to
/// such an address. So the screen never shows that text itself: only reasons
/// from this fixed list get their own sentence, and anything else is the
/// general one (HIN-179).
library;

/// The reasons the server sends after it refused a sign-in the identity
/// provider had accepted, each with a sentence under `auth.ssoRefused`.
const ssoRefusalReasons = {
  'ssoAccountNotLinked',
  'ssoEmailNotVerified',
  'ssoNoEmail',
  'accountDeactivated',
  'pendingApproval',
  'emailNotVerified',
};

/// The app's own reasons, set by the callback screen when the handoff failed.
const _appReasons = {
  'auth.ssoExchangeFailed',
  'auth.ssoNoCode',
  'auth.ssoTimedOut',
  'auth.ssoProviderFailed',
};

/// The i18n key for [reason]: its own sentence when it is one we know, the
/// general "the sign-in service did not complete it" otherwise.
///
/// [passwordSignIn] is whether the server takes passwords at all: an address
/// that belongs to an account not bound to this sign-in usually means a local
/// one, whose owner signs in with a password, but not where nobody can.
String ssoErrorKey(String? reason, {bool passwordSignIn = true}) {
  if (reason == null) return 'auth.ssoProviderFailed';
  if (_appReasons.contains(reason)) return reason;
  if (reason == 'ssoAccountNotLinked' && !passwordSignIn) {
    return 'auth.ssoRefused.ssoAccountNotLinkedSsoOnly';
  }
  if (ssoRefusalReasons.contains(reason)) return 'auth.ssoRefused.$reason';
  return 'auth.ssoProviderFailed';
}
