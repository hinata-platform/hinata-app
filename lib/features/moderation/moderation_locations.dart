import '../../core/models/moderation_case_models.dart' show CaseView;

/// Where the moderation pages live (HIN-174), written and read in one place: by
/// the pages, the router and the shell, which must not import the pages.

/// Where the moderation page shows [view], with case [caseId] open.
String moderationLocation({CaseView view = CaseView.open, String? caseId}) {
  final query = {if (view != CaseView.open) 'view': view.name, 'case': ?caseId};
  return Uri(
    path: '/moderation',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

/// The view [query] names as [moderationLocation] writes it; the open cases
/// for anything else.
CaseView caseViewOf(String? query) => CaseView.values.firstWhere(
  (view) => view.name == query,
  orElse: () => CaseView.open,
);

/// The suspended accounts, a page of the moderation page.
const suspensionsLocation = '/moderation/suspensions';

/// Where the notices live: every [noticeLocation] starts so.
const noticesPrefix = '/notices/';

/// Where the notice about case [caseId] lives: the bell and the mail lead
/// here, and so does "Why?" beside a removed post (HIN-173).
String noticeLocation(String caseId) =>
    '$noticesPrefix${Uri.encodeComponent(caseId)}';
