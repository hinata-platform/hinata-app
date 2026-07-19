import 'package:flutter/widgets.dart';

/// Smart-link resolution layer shared by the Knowledge Base and the real Issue
/// detail. The markdown renderer emits [SmartLinkChip]s for `{{issue:…}}`,
/// `{{doc:…}}` and `{{user:…}}` tokens; the chip and the `@`-mention field both
/// resolve those tokens against the ambient [SmartLinkResolver] — never against
/// a concrete repository — so the same widgets render in both worlds:
///
///  • In the KB reader/editor, issues/people come from the seed
///    ([KnowledgeLinkResolver]); clicking an issue chip bridges to the *real*
///    issue.
///  • In an issue, issues/people come from the backend
///    ([IssueLinkResolver]); doc chips still resolve against the KB.
///
/// The DTOs below are *display-ready* (icons + colors pre-resolved) so the chip
/// stays agnostic of each world's enum/color conventions.

/// An issue a `{{issue:…}}` token resolves to. [id] is the readable id (e.g.
/// `HIV-208`). All visual fields are pre-resolved by the resolver.
class SmartIssue {
  const SmartIssue({
    required this.id,
    required this.title,
    required this.typeIcon,
    required this.typeColor,
    required this.stateName,
    required this.stateColor,
    required this.priorityLabel,
    required this.priorityIcon,
    this.assigneeName,
    this.tags = const [],
  });

  final String id;
  final String title;
  final String typeIcon; // kebab-case lucide name
  final Color typeColor;
  final String stateName;
  final Color stateColor;
  final String priorityLabel;
  final String priorityIcon;
  final String? assigneeName;
  final List<String> tags;
}

/// An article a `{{doc:…}}` token resolves to. Articles live only in the KB, so
/// both resolvers fill this from the [KnowledgeRepository].
class SmartDoc {
  const SmartDoc({
    required this.id,
    required this.title,
    required this.icon,
    this.spaceName,
    this.spaceColor,
    this.authorName,
    this.updated,
    this.reads,
    this.excerpt = '',
  });

  final String id;
  final String title;
  final String icon; // kebab-case lucide name
  final String? spaceName;
  final Color? spaceColor;
  final String? authorName;
  final String? updated; // raw label; the preview appends " ago"
  final int? reads;
  final String excerpt;
}

/// A person a `{{user:…}}` token resolves to.
class SmartPerson {
  const SmartPerson({required this.id, required this.name, this.subtitle});

  final String id;
  final String name;
  final String? subtitle;

  String get firstName => name.split(' ').first;
}

/// A candidate row in the `@`-mention menu.
class MentionCandidate {
  const MentionCandidate({
    required this.kind, // issue | doc | user
    required this.id,
    required this.title,
    required this.sub,
    this.icon, // doc icon (kebab lucide)
    this.issueType, // type glyph for issue rows (kebab lucide)
    this.issueColor,
  });

  final String kind;
  final String id;
  final String title;
  final String sub;
  final String? icon;
  final String? issueType;
  final Color? issueColor;
}

/// Resolves smart-link tokens to display DTOs, handles clicks, and supplies
/// `@`-mention candidates. [mentions] is synchronous — doc/user candidates come
/// from in-memory lists so the menu stays snappy. Issue candidates may instead
/// be fetched from the backend on demand (see [asyncIssueMentions]) so a world
/// with a huge issue set never has to hold it all in memory.
abstract class SmartLinkResolver {
  SmartIssue? issue(String id);
  SmartDoc? doc(String id);
  SmartPerson? person(String id);

  void openIssue(String id);
  void openDoc(String id);
  void openPerson(String id);

  /// Synchronous candidates (always docs + people; issues too when
  /// [asyncIssueMentions] is false).
  List<MentionCandidate> mentions(String query, {required bool commentMode});

  /// When true, the mention menu fetches issue candidates via
  /// [searchIssueMentions] (debounced) instead of expecting them in [mentions] —
  /// used by the issue detail so it needn't drain the whole project issue set.
  /// The KB editor keeps its issues in [mentions] and returns false.
  bool get asyncIssueMentions => false;

  /// Debounced backend issue type-ahead for the menu; only called when
  /// [asyncIssueMentions] is true. Returns issue-kind [MentionCandidate]s.
  Future<List<MentionCandidate>> searchIssueMentions(String query) async =>
      const [];
}

/// Ambient access to the active [SmartLinkResolver]. Provided by the KB shell
/// and by the issue detail; consumed by [SmartLinkChip] and [MentionField].
class SmartLinkScope extends InheritedWidget {
  const SmartLinkScope({
    super.key,
    required this.resolver,
    required super.child,
  });

  final SmartLinkResolver resolver;

  static SmartLinkResolver of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SmartLinkScope>();
    assert(scope != null, 'No SmartLinkScope found in context');
    return scope!.resolver;
  }

  @override
  bool updateShouldNotify(SmartLinkScope oldWidget) =>
      resolver != oldWidget.resolver;
}
