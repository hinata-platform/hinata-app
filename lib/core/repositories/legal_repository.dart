import '../api/api_client.dart';

/// A legal document fetched from the server (operator-replaceable markdown).
class LegalDocumentContent {
  const LegalDocumentContent({
    required this.type,
    required this.lang,
    required this.markdown,
    this.updatedAt,
  });

  final String type;
  final String lang;
  final String markdown;
  final DateTime? updatedAt;

  factory LegalDocumentContent.fromJson(Map<String, dynamic> json) =>
      LegalDocumentContent(
        type: json['type'] as String? ?? '',
        lang: json['lang'] as String? ?? '',
        markdown: json['markdown'] as String? ?? '',
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.tryParse(json['updatedAt'] as String),
      );
}

/// Fetches the public legal documents (privacy policy / terms of service)
/// from `GET /api/v1/legal/{type}` — unauthenticated, works pre-login.
class LegalRepository {
  LegalRepository(this._api);

  final ApiClient _api;

  /// [type] is `privacy` or `terms`; [lang] `de` or `en`.
  Future<LegalDocumentContent> fetch(String type, String lang) async {
    final json = await _api.get('/api/v1/legal/$type', query: {'lang': lang});
    return LegalDocumentContent.fromJson(json as Map<String, dynamic>);
  }
}
