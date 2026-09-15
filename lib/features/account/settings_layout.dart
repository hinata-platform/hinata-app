import '../../core/responsive/golden_columns.dart';

/// A card on the wide settings page.
enum SettingsCard {
  security,
  sessions,
  notifications,
  timeTracking,
  availability,
  access,
  appearance,
  tokens,
  admin,
  data,
  danger,
}

/// The cards of the wide settings page in the groups that stay together, with
/// roughly how tall each group stands. [GoldenColumns] spreads them.
///
/// The notifications and the time cards are wide: their rows carry toggles,
/// steppers and pickers side by side. Time tracking and working hours grew with
/// every stage of HIN-60, which is why a fixed left column kept getting longer.
List<GoldenGroup<SettingsCard>> settingsGroups({
  required bool timeTracking,
  required bool tokens,
  required bool admin,
}) => [
  const GoldenGroup([
    SettingsCard.security,
    SettingsCard.sessions,
  ], weight: 7.4),
  const GoldenGroup([SettingsCard.notifications], weight: 7, wide: true),
  if (timeTracking)
    const GoldenGroup(
      [SettingsCard.timeTracking, SettingsCard.availability],
      weight: 23,
      wide: true,
    ),
  GoldenGroup([
    SettingsCard.access,
    SettingsCard.appearance,
    if (tokens) SettingsCard.tokens,
    if (admin) SettingsCard.admin,
  ], weight: 9.5 + (tokens ? 3 : 0) + (admin ? 1.5 : 0)),
  const GoldenGroup([SettingsCard.data, SettingsCard.danger], weight: 4.7),
];
