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
List<GoldenGroup<ProjectSettingsCard>> projectSettingsGroups({
  required bool timeTracking,
  required bool templates,
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
  const GoldenGroup([ProjectSettingsCard.git], weight: 9, wide: true),
  if (timeTracking)
    const GoldenGroup([ProjectSettingsCard.timeTracking], weight: 6),
  const GoldenGroup([
    ProjectSettingsCard.archive,
    ProjectSettingsCard.danger,
  ], weight: 3.8),
];
