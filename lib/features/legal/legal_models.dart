/// Which legal document to render. The content itself is operator-managed
/// markdown served by `GET /api/v1/legal/{type}` with a bundled asset fallback
/// (`assets/legal/{type}.{lang}.md`) so the public pages `/privacy-policy` and
/// `/terms-of-service` render even without a reachable server.
enum LegalDocType {
  privacy('privacy'),
  terms('terms');

  const LegalDocType(this.slug);

  /// Server + asset identifier (`privacy` / `terms`).
  final String slug;
}
