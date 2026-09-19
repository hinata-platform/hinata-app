import '../../core/responsive/golden_columns.dart';

/// A card on the wide settings page.
enum SettingsCard {
  security,
  appearance,
  sessions,
  notifications,
  timeTracking,
  availability,
  access,
  tokens,
  admin,
  data,
  danger,
}

/// The cards of the wide settings page in the groups that stay together, with
/// how tall each group was measured to stand. [GoldenColumns] spreads them.
///
/// Security leads: it is where the page starts and where somebody looking for
/// their account goes first, and appearance follows it directly — the server
/// somebody is connected to, their language and the light/dark choice are what
/// people come back to, and they were sitting four cards down. The only way to
/// keep a card under another one is to put it in the same group: the columns are
/// filled from the declaration, never rearranged by measured height.
///
/// The numbers are hundreds of points, read off the running app rather than
/// guessed, because guessing them went wrong: working hours was declared at 11
/// beside time tracking's 12 while it really stood more than twice as tall, and
/// the page reported level columns with one of them running a screenful past the
/// other. Each group is measured in the column kind it happened to sit in and
/// carried across at roughly a seventh, which is what the golden column's extra
/// width saves a card whose rows wrap.
List<GoldenGroup<SettingsCard>> settingsGroups({
  required bool timeTracking,
  required bool tokens,
  required bool admin,
}) => [
  const GoldenGroup.measured(
    [SettingsCard.security, SettingsCard.appearance],
    narrow: 9.8,
    golden: 8.95,
    lead: true,
  ),
  // Its own group, right behind the lead one: sessions read well under
  // appearance but do not have to stand there, and a small group the packer can
  // move is what keeps the columns level now that export and deletion are tied
  // to the admin entry. Declared here, so on a single column it still comes
  // third, where it always did.
  const GoldenGroup.measured([SettingsCard.sessions], narrow: 5.2, golden: 4.7),
  // Notifications and the two time cards are wide: their rows carry toggles,
  // steppers and pickers side by side, so a narrow column costs them the most.
  const GoldenGroup.measured(
    [SettingsCard.notifications],
    narrow: 13,
    golden: 11.1,
    wide: true,
  ),
  if (timeTracking) ...const [
    GoldenGroup.measured(
      [SettingsCard.timeTracking],
      narrow: 9,
      golden: 7.7,
      wide: true,
    ),
    // A third of the page while it also held the balances, the journal and the
    // absences; since those moved into the time module (HIN-117) it is the
    // weekday pattern, the holiday calendar and the way to the absences.
    // Measured at 688 points in a narrow column of the running app.
    GoldenGroup.measured(
      [SettingsCard.availability],
      narrow: 6.9,
      golden: 5.9,
      wide: true,
    ),
  ],
  // Export and deletion close the page, under the admin entry: they are the two
  // things somebody does to the account rather than with it, and they belong at
  // the end of the column somebody is already reading rather than alone at the
  // foot of another one. One group, because that is the only thing that keeps
  // one card under another.
  GoldenGroup.measured(
    [
      SettingsCard.access,
      if (tokens) SettingsCard.tokens,
      if (admin) SettingsCard.admin,
      SettingsCard.data,
      SettingsCard.danger,
    ],
    narrow: 5.5 + (tokens ? 3.9 : 0) + (admin ? 0.95 : 0),
    golden: 4.8 + (tokens ? 3.4 : 0) + (admin ? 0.8 : 0),
  ),
];
