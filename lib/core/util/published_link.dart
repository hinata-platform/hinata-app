/// What the app opens of an address a server published, such as its imprint,
/// its privacy policy or its house rules in `/meta` (HIN-26): https with a host
/// and no user info, or an address of [server] itself, which may be plain http
/// on a local network. Null for anything else.
///
/// An honest server takes only https addresses there, so this is the barrier
/// against a hostile one: on Windows a launcher hands a `file://` address or a
/// bare path to the shell, which connects out over SMB or runs a program.
Uri? publishedLink(String? value, {String? server}) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  if (uri.isScheme('https')) return uri;
  final own = server == null ? null : Uri.tryParse(server);
  final sameServer =
      own != null &&
      uri.isScheme('http') &&
      own.isScheme('http') &&
      own.host == uri.host &&
      own.port == uri.port;
  return sameServer ? uri : null;
}
