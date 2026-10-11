import 'package:equatable/equatable.dart';

/// Where in the knowledge base the screen is, read from the address.
///
/// Every view has its own address, so the browser's back button, a shared
/// link and a reload all land where the reader was. The screen derives what
/// it shows from this alone; nothing about the current view lives anywhere
/// else.
sealed class KnowledgeLocation extends Equatable {
  const KnowledgeLocation();

  /// The address of this view.
  String get path;

  @override
  List<Object?> get props => [path];
}

/// The start page: search, favourites, recently opened, spaces.
final class KnowledgeHomeLocation extends KnowledgeLocation {
  const KnowledgeHomeLocation();

  @override
  String get path => KnowledgePaths.home;
}

/// One space's overview: its page tree and what changed in it.
final class KnowledgeSpaceLocation extends KnowledgeLocation {
  const KnowledgeSpaceLocation(this.spaceId);

  final String spaceId;

  @override
  String get path => KnowledgePaths.space(spaceId);
}

/// A page, read.
final class KnowledgeArticleLocation extends KnowledgeLocation {
  const KnowledgeArticleLocation(this.articleId);

  final String articleId;

  @override
  String get path => KnowledgePaths.article(articleId);
}

/// A page, edited.
final class KnowledgeEditLocation extends KnowledgeLocation {
  const KnowledgeEditLocation(this.articleId);

  final String articleId;

  @override
  String get path => KnowledgePaths.edit(articleId);
}

/// A new page, in [spaceId] and under [parentId] when given.
final class KnowledgeNewLocation extends KnowledgeLocation {
  const KnowledgeNewLocation({this.spaceId, this.parentId});

  final String? spaceId;
  final String? parentId;

  @override
  String get path =>
      KnowledgePaths.create(spaceId: spaceId, parentId: parentId);
}

/// A page's history, with [version] open when given.
final class KnowledgeHistoryLocation extends KnowledgeLocation {
  const KnowledgeHistoryLocation(this.articleId, {this.version});

  final String articleId;
  final int? version;

  @override
  String get path => KnowledgePaths.history(articleId, version: version);
}

/// The knowledge base's addresses, in one place so a link elsewhere in the
/// app cannot drift from the routes.
abstract final class KnowledgePaths {
  static const home = '/knowledge';

  static String space(String spaceId) =>
      '/knowledge/spaces/${Uri.encodeComponent(spaceId)}';

  static String article(String id) => '/knowledge/${Uri.encodeComponent(id)}';

  static String edit(String id) => '${article(id)}/edit';

  static String history(String id, {int? version}) =>
      '${article(id)}/history${version == null ? '' : '?v=$version'}';

  static String create({String? spaceId, String? parentId}) => Uri(
    path: '/knowledge/new',
    queryParameters: {
      if (spaceId != null && spaceId.isNotEmpty) 'space': spaceId,
      'parent': ?parentId,
    },
  ).toString().replaceFirst(RegExp(r'\?$'), '');
}
