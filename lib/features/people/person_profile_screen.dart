import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/moderation_models.dart';
import '../../core/repositories/admin_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../admin/users/user_actions.dart';
import '../admin/users/user_management_cubit.dart';
import '../admin/users/user_management_widgets.dart' show UserAdminSections;
import '../blocks/block_actions.dart';
import '../blocks/hidden_content_cubit.dart';
import '../moderation/report/report_sheet.dart';
import '../shell/page_chrome.dart';
import 'person_admin_cubit.dart';
import 'person_profile_cubit.dart';
import 'person_profile_view.dart';

/// Where a person's profile lives (HIN-165).
const peopleRoute = '/people';

String personLocation(String id) => '$peopleRoute/${Uri.encodeComponent(id)}';

/// How a profile was opened: from inside the app, over the page somebody is
/// on, or by its address alone.
class PersonRouteArgs {
  const PersonRouteArgs({this.panel = false});

  /// Opened from a page, so on a wide window it slides in from the right over
  /// that page instead of replacing it.
  final bool panel;
}

/// Opens [personId]'s profile from anywhere in the app: a side panel over the
/// current page on a wide window, a page of its own with a way back on a
/// phone. Either way the address is the profile's, so a link to it works too.
Future<void> openPersonProfile(BuildContext context, String personId) =>
    context.push<void>(
      personLocation(personId),
      extra: const PersonRouteArgs(panel: true),
    );

/// The page for `/people/:id`.
///
/// A profile opened from a page on a wide window is a panel over that page,
/// like the admin area's user drawer; anything else (a phone, a link opened
/// cold, a reload) is a page of its own, because there is no page beneath to
/// slide over.
Page<void> personProfilePage(
  BuildContext context,
  GoRouterState state, {
  required Page<void> Function(GoRouterState state, Widget child) fullPage,
}) {
  final id = state.pathParameters['id']!;
  final extra = state.extra;
  final panel = extra is PersonRouteArgs && extra.panel && !context.isCompact;
  if (!panel) {
    return fullPage(
      state,
      PersonProfileScreen(key: ValueKey('person-$id'), personId: id),
    );
  }
  return _PersonPanelPage(
    key: state.pageKey,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    child: PersonProfileScreen(
      key: ValueKey('person-$id'),
      personId: id,
      panel: true,
    ),
  );
}

/// The profile panel's page. Its route is a popup, not a page route: a page
/// route over the shell makes the page beneath play its exit transition
/// (the shared-axis fade), and the panel then slid in over an empty pane
/// instead of over the page it was opened from.
class _PersonPanelPage extends Page<void> {
  const _PersonPanelPage({
    super.key,
    required this.barrierLabel,
    required this.child,
  });

  final String barrierLabel;
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) =>
      _PersonPanelRoute(page: this);
}

class _PersonPanelRoute extends PopupRoute<void> {
  _PersonPanelRoute({required _PersonPanelPage page}) : super(settings: page);

  _PersonPanelPage get _page => settings as _PersonPanelPage;

  @override
  Color? get barrierColor => Colors.black.withValues(alpha: 0.32);

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => _page.barrierLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}

/// A person's profile, as a page or as a side panel ([panel]).
class PersonProfileScreen extends StatelessWidget {
  const PersonProfileScreen({
    super.key,
    required this.personId,
    this.panel = false,
  });

  final String personId;
  final bool panel;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        PersonProfileCubit(context.read<UserRepository>(), personId)..load(),
    child: _PersonProfileBody(panel: panel),
  );
}

class _PersonProfileBody extends StatelessWidget {
  const _PersonProfileBody({required this.panel});

  final bool panel;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PersonProfileCubit>().state;
    final profile = state.profile;
    if (panel) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SafeArea(
            left: false,
            child: SizedBox(
              width: 440,
              child: GlassFloatingSurface(
                radius: AppTheme.radiusDialog,
                child: _content(context, state, padding: _panelPadding),
              ),
            ),
          ),
        ),
      );
    }
    return PageChrome(
      title: profile?.displayName ?? context.t('people.title'),
      child: _content(context, state, padding: context.pagePadding),
    );
  }

  static const _panelPadding = EdgeInsets.fromLTRB(20, 18, 12, 28);

  Widget _content(
    BuildContext context,
    PersonProfileState state, {
    required EdgeInsets padding,
  }) {
    final profile = state.profile;
    if (profile == null) {
      if (state.status == PersonProfileStatus.loading) {
        return const Center(child: HiveLoader());
      }
      final notFound = state.status == PersonProfileStatus.notFound;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HiveEmptyState(
            title: context.t(
              notFound ? 'people.notFound.title' : 'people.loadFailed',
            ),
            message: notFound
                ? context.t('people.notFound.message')
                : context.t(state.errorKey ?? 'errors.unexpected'),
            action: OutlinedButton(
              onPressed: notFound
                  ? () => _leave(context)
                  : () => unawaited(context.read<PersonProfileCubit>().load()),
              child: Text(context.t(notFound ? 'common.back' : 'common.retry')),
            ),
          ),
        ),
      );
    }
    final email = profile.email;
    final canBlock =
        !profile.self &&
        (context.read<AppConfigBloc?>()?.state.meta?.supportsModeration ??
            false);
    final blocked = context.select<HiddenContentCubit?, bool>(
      (hidden) => hidden?.state.blocks(profile.id) ?? false,
    );
    return PersonProfileView(
      profile: profile,
      clockReady: state.clockReady,
      padding: padding,
      blocked: blocked,
      actions: PersonProfileActions(
        openIssues: () => context.go(
          Uri(
            path: '/issues',
            queryParameters: {'assignee': profile.id},
          ).toString(),
        ),
        openTeam: (id) => context.go('/teams/$id'),
        openProject: (id) => context.go(
          Uri(path: '/issues', queryParameters: {'projectId': id}).toString(),
        ),
        writeEmail: email == null
            ? null
            : () => unawaited(launchUrl(Uri(scheme: 'mailto', path: email))),
        toggleBlock: canBlock
            ? () => unawaited(
                blocked
                    ? liftBlock(
                        context,
                        personId: profile.id,
                        name: profile.displayName,
                      )
                    : confirmBlock(
                        context,
                        personId: profile.id,
                        name: profile.displayName,
                      ),
              )
            : null,
        report: canBlock
            ? (anchor) => unawaited(
                showReportSheet(
                  context,
                  anchorRect: anchor,
                  subject: ReportSubject(
                    target: TargetRef(ContentKind.person, profile.id),
                    title: context.t('moderation.report.titlePerson'),
                    subtitle: profile.displayName,
                    authorId: blocked ? null : profile.id,
                    authorName: profile.displayName,
                  ),
                ),
              )
            : null,
        close: panel ? () => _leave(context) : null,
      ),
      admin: profile.canAdmin ? _PersonAdmin(personId: profile.id) : null,
    );
  }

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/dashboard');
    }
  }
}

/// The account's administration inside the profile, for a reader who holds
/// the platform role: the admin area's own sections and actions.
class _PersonAdmin extends StatelessWidget {
  const _PersonAdmin({required this.personId});

  final String personId;

  /// Both cubits are the profile's own, provided here so they close with it:
  /// one reads the account, the other carries out the admin area's actions.
  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (context) =>
            PersonAdminCubit(context.read<AdminRepository>(), personId)..load(),
      ),
      BlocProvider(
        create: (context) =>
            UserManagementCubit(context.read<AdminRepository>()),
      ),
    ],
    child: const _PersonAdminBody(),
  );
}

class _PersonAdminBody extends StatelessWidget {
  const _PersonAdminBody();

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<PersonAdminCubit>();
    final state = admin.state;
    final user = state.user;
    if (user == null) {
      if (state.loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: HiveLoader(size: 28)),
        );
      }
      return Row(
        children: [
          Expanded(
            child: Text(
              context.t(state.errorKey ?? 'errors.unexpected'),
              style: TextStyle(color: AppColors.inkSoft),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(admin.load()),
            child: Text(context.t('common.retry')),
          ),
        ],
      );
    }
    final actions = buildUserActions(
      context,
      users: context.read<UserManagementCubit>(),
      currentUserId: context.read<AuthBloc>().state.user?.id,
      // The profile knows that of its own person only.
      isLastActiveAdmin: (u) => u.id == user.id && state.lastActiveAdmin,
      // The profile knows one person; an inviter is named where the directory
      // knows them, and simply not named here.
      nameById: (_) => null,
      usersFor: (ids) => [if (ids.contains(user.id)) user],
      reload: () async {
        final profile = context.read<PersonProfileCubit>();
        await Future.wait([admin.load(), profile.load()]);
      },
    );
    return UserAdminSections(user: user, actions: actions);
  }
}
