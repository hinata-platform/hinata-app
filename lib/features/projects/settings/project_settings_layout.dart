import '../../../core/responsive/golden_columns.dart';

/// A card on the project settings page.
enum ProjectSettingsCard {
  general,
  templates,
  members,
  labels,
  workflow,
  git,
  timeTracking,
  archive,
  danger,
}

/// The cards of the project settings page in the groups that stay together,
/// with roughly how tall each group stands. [GoldenColumns] spreads them.
///
/// General leads: it is the card that names the project, and a settings page
/// whose first card is somewhere else reads as a page you have opened by
/// mistake. The workflow and the git integration are wide: their rows carry a
/// handle, a name, toggles and actions side by side. Members and labels are the
/// team's vocabulary and stay together, archive and deletion close the page.
///
/// [lead] is false for a Team-Admin of an owning team who does not lead the
/// project: the git integration and the deletion stay with the leads, so those
/// cards are not on their page at all.
List<GoldenGroup<ProjectSettingsCard>> projectSettingsGroups({
  required bool timeTracking,
  required bool templates,
  bool lead = true,
}) => [
  const GoldenGroup([ProjectSettingsCard.general], weight: 5.5, lead: true),
  // The project's date, its template marker and the copy. Short — three rows
  // and a button — so it rides with whichever column has room.
  if (templates)
    const GoldenGroup([ProjectSettingsCard.templates], weight: 3.2),
  const GoldenGroup([
    ProjectSettingsCard.members,
    ProjectSettingsCard.labels,
  ], weight: 7),
  const GoldenGroup([ProjectSettingsCard.workflow], weight: 6, wide: true),
  if (lead) const GoldenGroup([ProjectSettingsCard.git], weight: 9, wide: true),
  if (timeTracking)
    const GoldenGroup([ProjectSettingsCard.timeTracking], weight: 6),
  if (lead)
    const GoldenGroup([
      ProjectSettingsCard.archive,
      ProjectSettingsCard.danger,
    ], weight: 3.8)
  else
    const GoldenGroup([ProjectSettingsCard.archive], weight: 1.6),
];

/// The sections of the project settings page on a wide window, in rail order
/// (HIN-110). Each card is one section; the rail shows one at a time.
///
/// General opens the page: naming and describing the project is what people
/// come here for most. The people and the template come next, then how work
/// is shaped (labels, states, time), the git integration, and last the archive
/// and the deletion, the danger zone on its own at the very end. The same
/// cards as [projectSettingsGroups], so a phone and a desktop never disagree
/// about what is on the page.
List<ProjectSettingsCard> projectSettingsSections({
  required bool timeTracking,
  required bool templates,
  bool lead = true,
}) => [
  ProjectSettingsCard.general,
  ProjectSettingsCard.members,
  if (templates) ProjectSettingsCard.templates,
  ProjectSettingsCard.labels,
  ProjectSettingsCard.workflow,
  if (timeTracking) ProjectSettingsCard.timeTracking,
  if (lead) ProjectSettingsCard.git,
  ProjectSettingsCard.archive,
  if (lead) ProjectSettingsCard.danger,
];

/// The section a `?section=` deep link names, by the card's name
/// (`general`, `members`, `git`, …); null for anything else.
ProjectSettingsCard? projectSettingsSectionFromQuery(String? value) {
  if (value == null) return null;
  for (final card in ProjectSettingsCard.values) {
    if (card.name == value) return card;
  }
  return null;
}
