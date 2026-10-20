import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
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
  return CustomTransitionPage<void>(
    key: state.pageKey,
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: PersonProfileScreen(
      key: ValueKey('person-$id'),
      personId: id,
      panel: true,
    ),
    transitionsBuilder: (context, animation, _, child) {
      if (MediaQuery.disableAnimationsOf(context)) {
        return FadeTransition(opacity: animation, child: child);
      }
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      );
    },
  );
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
    return PersonProfileView(
      profile: profile,
      clockReady: state.clockReady,
      padding: padding,
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

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => PersonAdminCubit(
      UserManagementCubit(context.read<AdminRepository>()),
      personId,
    )..load(),
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
      users: admin.users,
      currentUserId: context.read<AuthBloc>().state.user?.id,
      isLastActiveAdmin: (_) => state.lastActiveAdmin,
      // The profile knows one person; an inviter is named where the directory
      // knows them, and simply not named here.
      nameById: (_) => null,
      usersFor: (ids) => [if (ids.contains(user.id)) user],
      openDrawer: (_, _) {},
      reload: () async {
        final profile = context.read<PersonProfileCubit>();
        await Future.wait([admin.load(), profile.load()]);
      },
    );
    return UserAdminSections(user: user, actions: actions, onDismiss: () {});
  }
}
