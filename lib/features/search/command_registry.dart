import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/theme_cubit.dart';
import '../time/time_commands.dart';
import 'search_models.dart' show SearchModules;

/// What the ⌘K palette can *do*, as opposed to what it can find.
///
/// One registry, grouped per feature, rather than a literal inside the
/// palette's controller: the controller's list was private and had no way to
/// know about the time module, which is how it came to be missing
/// `/timesheet`. Most groups live in this file ([kNavigationCommands],
/// [kShiftCommands], [kBillingCommands], [kAdminCommands] and so on); the time
/// module brings its own ([kTimeCommands]) because its commands act rather
/// than only navigate. [paletteCommands] puts the groups together for the
/// reader.
///
/// The palette turns these into its own rows; nothing here knows what a row
/// looks like.
@immutable
class PaletteCommand {
  const PaletteCommand({
    required this.id,
    required this.labelKey,
    required this.icon,
    this.route,
    this.onSelect,
    this.keywords = '',
    this.hint,
    this.closesOnSelect = true,
    this.contextKey,
  }) : assert(
         route != null || onSelect != null,
         'A command either goes somewhere or does something.',
       );

  /// A command that only navigates somewhere. The overwhelming majority, and
  /// the reason the list can be `const`: a closure is not a constant, and one
  /// per destination would be a closure per row that all say `context.go`.
  const PaletteCommand.route({
    required this.id,
    required this.labelKey,
    required this.icon,
    required String this.route,
    this.keywords = '',
    this.hint,
    this.contextKey,
  }) : onSelect = null,
       closesOnSelect = true;

  final String id;
  final String labelKey;
  final IconData icon;

  /// Extra words that should find it, in English and lower case — a reader
  /// searching "pomodoro" should land on the focus mode whatever it is called
  /// in their language. The localized label is added to these by the palette.
  final String keywords;

  /// A key hint shown on the row, where one exists.
  final String? hint;

  /// The page a section or a view belongs to, shown under its name: "Security"
  /// is a part of the settings and a part of the admin area, and the row has to
  /// say which one it opens. Null for a page that names itself.
  final String? contextKey;

  /// Whether choosing it dismisses the palette. False for a toggle somebody may
  /// want to press twice.
  final bool closesOnSelect;

  /// Where it goes, for a navigation command; null for one that acts.
  final String? route;

  /// What it does, for one that acts; null for one that only navigates.
  final void Function(BuildContext context)? onSelect;

  void invoke(BuildContext context) {
    final route = this.route;
    if (route != null) {
      context.go(route);
      return;
    }
    onSelect!(context);
  }
}

/// Who is asking and what this server runs: everything that decides whether a
/// page is there for the reader at all.
///
/// A command is only listed where the page it opens would show the reader
/// something. A row that leads to a not-found page, or to a page that can only
/// say "not for you", is worse than a row fewer.
@immutable
class PaletteAccess {
  const PaletteAccess({
    this.modules = const SearchModules(),
    this.admin = false,
    this.orgAdmin = false,
    this.mcp = false,
    this.workloadReports = false,
    this.absenceReports = false,
    this.approvals = false,
  });

  final SearchModules modules;

  /// Holds the platform role: the admin area is theirs.
  final bool admin;

  /// Holds the organisation role: the organisation page, billing's own pages
  /// and the money report are theirs.
  final bool orgAdmin;

  /// Personal access tokens are offered (the `mcp` flag).
  final bool mcp;

  /// The organisation lets reports show booked time against capacity.
  final bool workloadReports;

  /// The organisation lets reports show absences.
  final bool absenceReports;

  /// The organisation has timesheet approvals switched on.
  final bool approvals;
}

/// Everything on offer right now, to [access].
///
/// Every page of the navigation is in here by name, each of its views and
/// sections too: somebody looking for the shift calendar or for the sessions
/// of their account should not have to know first which page it sits under.
List<PaletteCommand> paletteCommands(PaletteAccess access) {
  final modules = access.modules;
  return [
    ...kNavigationCommands,
    if (!modules.advancedTime) ...kBaseTimeCommands,
    ...kAppCommands,
    if (modules.advancedTime) ...kTimeCommands,
    if (modules.advancedTime && access.approvals) kTimeApprovalsCommand,
    if (modules.advancedTime) ...reportCommands(access),
    if (modules.billing && access.orgAdmin) ...kBillingCommands,
    if (modules.shifts) ...kShiftCommands,
    ...accountCommands(access),
    if (access.admin) ...kAdminCommands,
    if (access.orgAdmin) ...kOrganizationCommands,
  ];
}

/// Going somewhere. The app's primary destinations, in the order the rail has
/// them.
const List<PaletteCommand> kNavigationCommands = [
  PaletteCommand.route(
    id: 'nav.dashboard',
    labelKey: 'search.cmd.dashboard',
    icon: LucideIcons.layoutDashboard,
    route: '/dashboard',
    keywords: 'navigate jump home',
  ),
  PaletteCommand.route(
    id: 'nav.projects',
    labelKey: 'search.cmd.projects',
    icon: LucideIcons.squareKanban,
    route: '/projects',
    keywords: 'navigate jump',
  ),
  PaletteCommand.route(
    id: 'nav.issues',
    labelKey: 'search.cmd.issues',
    icon: LucideIcons.circleCheck,
    route: '/issues',
    keywords: 'navigate jump tickets',
  ),
  PaletteCommand.route(
    id: 'nav.board',
    labelKey: 'search.cmd.board',
    icon: LucideIcons.columns3,
    route: '/board',
    keywords: 'navigate jump kanban',
  ),
  PaletteCommand.route(
    id: 'nav.timeline',
    labelKey: 'search.cmd.timeline',
    icon: LucideIcons.chartColumnStacked,
    route: '/gantt',
    keywords: 'navigate jump gantt',
  ),
  PaletteCommand.route(
    id: 'nav.reports',
    labelKey: 'search.cmd.reports',
    icon: LucideIcons.chartLine,
    route: '/reports',
    keywords: 'navigate jump',
  ),
  PaletteCommand.route(
    id: 'nav.knowledge',
    labelKey: 'search.cmd.knowledge',
    icon: LucideIcons.bookOpen,
    route: '/knowledge',
    keywords: 'navigate jump wiki docs',
  ),
  PaletteCommand.route(
    id: 'nav.teams',
    labelKey: 'nav.teams',
    icon: LucideIcons.usersRound,
    route: '/teams',
    keywords: 'navigate jump teams groups',
  ),
  PaletteCommand.route(
    id: 'nav.watched',
    labelKey: 'nav.watched',
    icon: LucideIcons.eye,
    route: '/watched',
    keywords: 'navigate jump watched watching follow',
  ),
  PaletteCommand.route(
    id: 'nav.notifications',
    labelKey: 'nav.notifications',
    icon: LucideIcons.bell,
    route: '/notifications',
    keywords: 'navigate jump notifications inbox bell',
  ),
  PaletteCommand.route(
    id: 'nav.weeklySummary',
    labelKey: 'weeklySummary.title',
    icon: LucideIcons.calendarRange,
    route: '/weekly-summary',
    keywords: 'navigate jump weekly summary digest week',
  ),
];

/// Doing something, rather than going somewhere.
final List<PaletteCommand> kAppCommands = [
  const PaletteCommand.route(
    id: 'app.newIssue',
    labelKey: 'search.cmd.newIssue',
    icon: LucideIcons.plus,
    route: '/board',
    keywords: 'new issue create add task bug',
    hint: 'C',
  ),
  PaletteCommand(
    id: 'app.theme',
    labelKey: 'search.cmd.toggleTheme',
    icon: LucideIcons.sunMoon,
    keywords: 'theme dark light appearance mode',
    closesOnSelect: false,
    onSelect: (context) {
      final cubit = context.read<ThemeCubit>();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      cubit.setMode(isDark ? ThemeMode.light : ThemeMode.dark);
    },
  ),
];

/// The base timesheet, on a server without the extended module. With it on,
/// the module's own commands lead to its timesheet instead.
const List<PaletteCommand> kBaseTimeCommands = [
  PaletteCommand.route(
    id: 'nav.timesheet',
    labelKey: 'search.cmd.timesheet',
    icon: LucideIcons.table,
    route: '/timesheet',
    keywords: 'timesheet grid week hours time',
  ),
];

/// The report page's tabs, each only where the reader would find it there.
List<PaletteCommand> reportCommands(PaletteAccess access) => [
  for (final (tab, icon, keywords) in const [
    ('overview', LucideIcons.layoutDashboard, 'project overview'),
    ('budgets', LucideIcons.hourglass, 'budgets budget'),
    ('summary', LucideIcons.chartColumn, 'summary chart'),
    ('detailed', LucideIcons.list, 'detailed entries'),
    ('workload', LucideIcons.gauge, 'workload capacity utilization'),
    ('absences', LucideIcons.calendarOff, 'absences vacation'),
    ('billing', LucideIcons.coins, 'billing revenue money'),
    ('saved', LucideIcons.bookmark, 'saved bookmarked'),
  ])
    if ((tab != 'workload' || access.workloadReports) &&
        (tab != 'absences' ||
            access.absenceReports && access.modules.absences) &&
        (tab != 'billing' || access.modules.billing && access.orgAdmin))
      PaletteCommand.route(
        id: 'reports.$tab',
        labelKey: 'time.reports.tab.$tab',
        contextKey: 'nav.reports',
        icon: icon,
        route: '/time/reports?tab=$tab',
        keywords: 'reports report $keywords',
      ),
];

/// Billing's own pages (HIN-96), for the organisation admin who keeps them.
const List<PaletteCommand> kBillingCommands = [
  PaletteCommand.route(
    id: 'billing.rates',
    labelKey: 'billing.rates.title',
    icon: LucideIcons.coins,
    route: '/time/rates',
    keywords: 'billing rates hourly rate price',
  ),
  PaletteCommand.route(
    id: 'billing.invoices',
    labelKey: 'billing.invoices.title',
    icon: LucideIcons.receiptText,
    route: '/time/invoices',
    keywords: 'billing invoices invoice bill',
  ),
];

/// Shift planning's three views (HIN-27).
const List<PaletteCommand> kShiftCommands = [
  PaletteCommand.route(
    id: 'shifts.mine',
    labelKey: 'search.cmd.shifts',
    icon: LucideIcons.calendarClock,
    route: '/shifts',
    keywords: 'shifts my shifts rota schedule duty',
  ),
  PaletteCommand.route(
    id: 'shifts.calendar',
    labelKey: 'shifts.view.calendar',
    contextKey: 'nav.shifts',
    icon: LucideIcons.calendarDays,
    route: '/shifts/calendar',
    keywords: 'shifts calendar month week',
  ),
  PaletteCommand.route(
    id: 'shifts.events',
    labelKey: 'shifts.view.events',
    contextKey: 'nav.shifts',
    icon: LucideIcons.calendarRange,
    route: '/shifts/events',
    keywords: 'shifts events event planning',
  ),
];

/// One's own settings and each of their sections, opened directly.
List<PaletteCommand> accountCommands(PaletteAccess access) => [
  const PaletteCommand.route(
    id: 'nav.settings',
    labelKey: 'nav.settings',
    icon: LucideIcons.settings,
    route: '/settings',
    keywords: 'settings account preferences profile',
  ),
  for (final (section, labelKey, icon, keywords) in const [
    (
      'security',
      'account.security.title',
      LucideIcons.shieldCheck,
      'security password two factor 2fa profile',
    ),
    (
      'sessions',
      'account.sessions.title',
      LucideIcons.monitorSmartphone,
      'sessions devices signed in logout',
    ),
    (
      'notifications',
      'account.notifications.title',
      LucideIcons.bell,
      'notifications email push quiet hours',
    ),
    (
      'time',
      'account.timeTracking.title',
      LucideIcons.timer,
      'time tracking working hours timer',
    ),
    (
      'access',
      'account.access.title',
      LucideIcons.layers,
      'access teams projects',
    ),
    (
      'appearance',
      'account.appearance.title',
      LucideIcons.sunMoon,
      'appearance theme dark light color language',
    ),
    (
      'tokens',
      'account.tokens.title',
      LucideIcons.keyRound,
      'tokens personal access token api mcp',
    ),
    (
      'data',
      'account.data.title',
      LucideIcons.fileText,
      'data export privacy gdpr download',
    ),
    (
      'danger',
      'account.danger.title',
      LucideIcons.triangleAlert,
      'danger delete account',
    ),
  ])
    if ((section != 'tokens' || access.mcp) &&
        (section != 'time' || access.modules.advancedTime))
      PaletteCommand.route(
        id: 'settings.$section',
        labelKey: labelKey,
        contextKey: 'nav.settings',
        icon: icon,
        route: '/settings?section=$section',
        keywords: 'settings account $keywords',
      ),
];

/// The admin area and its sections, for those who hold the platform role.
const List<PaletteCommand> kAdminCommands = [
  PaletteCommand.route(
    id: 'admin',
    labelKey: 'admin.title',
    icon: LucideIcons.shieldUser,
    route: '/admin',
    keywords: 'admin administration area',
  ),
  PaletteCommand.route(
    id: 'admin.general',
    labelKey: 'admin.general',
    contextKey: 'admin.title',
    icon: LucideIcons.building2,
    route: '/admin?section=general',
    keywords: 'admin general organisation organization name logo',
  ),
  PaletteCommand.route(
    id: 'admin.app',
    labelKey: 'admin.app',
    contextKey: 'admin.title',
    icon: LucideIcons.smartphone,
    route: '/admin?section=app',
    keywords: 'admin app modules feature flags version',
  ),
  PaletteCommand.route(
    id: 'admin.security',
    labelKey: 'admin.security',
    contextKey: 'admin.title',
    icon: LucideIcons.shield,
    route: '/admin?section=security',
    keywords: 'admin security policy password',
  ),
  PaletteCommand.route(
    id: 'admin.authentication',
    labelKey: 'admin.authentication',
    contextKey: 'admin.title',
    icon: LucideIcons.lock,
    route: '/admin?section=authentication',
    keywords: 'admin authentication sso oidc login',
  ),
  PaletteCommand.route(
    id: 'admin.connect',
    labelKey: 'admin.connect',
    contextKey: 'admin.title',
    icon: LucideIcons.radioTower,
    route: '/admin?section=connect',
    keywords: 'admin connect push relay',
  ),
  PaletteCommand.route(
    id: 'admin.email',
    labelKey: 'admin.email',
    contextKey: 'admin.title',
    icon: LucideIcons.mail,
    route: '/admin?section=email',
    keywords: 'admin email smtp mail',
  ),
  PaletteCommand.route(
    id: 'admin.git',
    labelKey: 'admin.gitIntegration',
    contextKey: 'admin.title',
    icon: LucideIcons.gitBranch,
    route: '/admin?section=git',
    keywords: 'admin git github gitlab integration',
  ),
  PaletteCommand.route(
    id: 'admin.mcp',
    labelKey: 'admin.mcp',
    contextKey: 'admin.title',
    icon: LucideIcons.plug,
    route: '/admin?section=mcp',
    keywords: 'admin mcp ai assistant',
  ),
  PaletteCommand.route(
    id: 'admin.auditLog',
    labelKey: 'admin.auditLog',
    contextKey: 'admin.title',
    icon: LucideIcons.history,
    route: '/admin?section=auditLog',
    keywords: 'admin audit log history',
  ),
  PaletteCommand.route(
    id: 'admin.users',
    labelKey: 'admin.users',
    contextKey: 'admin.title',
    icon: LucideIcons.users,
    route: '/admin?section=users',
    keywords: 'admin users people accounts invite',
  ),
];

/// The organisation page, for those who hold the organisation role.
const List<PaletteCommand> kOrganizationCommands = [
  PaletteCommand.route(
    id: 'organization',
    labelKey: 'org.title',
    icon: LucideIcons.building,
    route: '/organization',
    keywords: 'organisation organization time tracking absences billing',
  ),
  PaletteCommand.route(
    id: 'organization.holidays',
    labelKey: 'availability.admin.pageTitle',
    contextKey: 'org.title',
    icon: LucideIcons.calendarHeart,
    route: '/organization/holidays',
    keywords: 'holidays public holidays calendar',
  ),
  PaletteCommand.route(
    id: 'organization.audit',
    labelKey: 'org.audit.title',
    contextKey: 'org.title',
    icon: LucideIcons.history,
    route: '/organization/audit',
    keywords: 'organisation organization audit log history',
  ),
];
