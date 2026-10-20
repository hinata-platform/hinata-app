import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/search_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/hue_colors.dart' show colorFromHex;
import '../../core/widgets/hive_widgets.dart' show fmtDuration, stateLabel;
import '../billing/billing_format.dart' show formatMoney;
import '../issues/attachments/attachment_kind.dart'
    show formatBytes, relativeAgeLabel;
import '../people/person_profile_screen.dart'
    show openPersonProfile, peopleRoute;
import '../teams/team_widgets.dart' show teamHueColor, teamIcon;
import 'search_models.dart';

/// Everything a hit's row needs said in the reader's language: words, days,
/// hours and money.
///
/// Captured once from the context that opens the palette, because the rows are
/// composed in the controller, which has no context of its own and should not
/// hold one; tests hand in their own.
class SearchLabels {
  SearchLabels({
    required this.t,
    required this.day,
    required this.time,
    required this.duration,
    required this.money,
    required this.ago,
  });

  /// Reads the labels from the context the palette is opened from.
  factory SearchLabels.of(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return SearchLabels(
      t: (key, [variables]) => context.t(key, variables: variables),
      day: (date) => DateFormat.MMMEd(locale).format(date),
      time: (date) => DateFormat.Hm(locale).format(date),
      duration: (minutes) => fmtDuration(context, minutes),
      money: (cents, currency) => formatMoney(context, cents, currency),
      ago: (when) => relativeAgeLabel(context, when),
    );
  }

  final String Function(String key, [Map<String, dynamic>? variables]) t;
  final String Function(DateTime date) day;
  final String Function(DateTime date) time;
  final String Function(int minutes) duration;
  final String Function(int cents, String currency) money;
  final String Function(DateTime when) ago;

  /// A span of days, `Mo., 19. Okt.` or `Mo., 19. Okt. – Fr., 23. Okt.`.
  String days(DateTime from, DateTime? to) =>
      to == null || to == from ? day(from) : '${day(from)} – ${day(to)}';

  /// A span in time, `Sa., 24. Okt. 14:00–18:00`; a span over midnight names
  /// both days.
  String moment(DateTime start, DateTime? end) {
    if (end == null) return '${day(start)} ${time(start)}';
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    return sameDay
        ? '${day(start)} ${time(start)}–${time(end)}'
        : '${day(start)} ${time(start)} – ${day(end)} ${time(end)}';
  }
}

/// Turns one server hit into the palette's row: what it is called, what stands
/// under it, the glyph before it, and where choosing it goes.
///
/// The server decides where a hit leads (`route`) and what the reader may see;
/// this only decides how it reads. Pieces of a subtitle are joined with a
/// middle dot, which reads the same in every language the app speaks, so only
/// the words themselves need translating.
SearchEntry mapSearchHit(SearchApiHit hit, SearchLabels l) {
  final cat = searchCatFromName(hit.category) ?? SearchCat.issues;
  void open(BuildContext context) => context.go(hit.route);
  String? joined(List<String?> parts) {
    final kept = [
      for (final part in parts)
        if (part != null && part.trim().isNotEmpty) part.trim(),
    ];
    return kept.isEmpty ? null : kept.join(' · ');
  }

  SearchEntry entry({
    required String prefix,
    String? subtitle,
    IconData? icon,
    Color? color,
    String? keys,
    bool muted = false,
  }) => SearchEntry(
    cat: cat,
    key: '$prefix-${hit.id}',
    title: hit.title,
    keys: (keys ?? hit.title).toLowerCase(),
    subtitle: subtitle,
    leadingIcon: icon,
    leadingColor: color,
    keyChipText: hit.projectKey,
    keyChipColor: hit.projectColor == null
        ? null
        : colorFromHex(hit.projectColor!),
    muted: muted,
    onSelect: open,
  );

  switch (cat) {
    case SearchCat.issues:
      return SearchEntry(
        cat: cat,
        key: 'i-${hit.id}',
        title: hit.title,
        keys: hit.title.toLowerCase(),
        mono: hit.readableId,
        issueType: hit.type,
        statusColor: hit.state != null
            ? AppColors.stateColor(hit.state!)
            : null,
        statusName: hit.state != null ? stateLabel(hit.state!) : null,
        avatarName: hit.assigneeName,
        avatarUrl: hit.assigneeAvatarUrl,
        archived: hit.archived,
        onSelect: open,
      );
    case SearchCat.comments:
      return entry(
        prefix: 'c',
        icon: LucideIcons.messageSquare,
        subtitle: joined([
          hit.readableId,
          hit.subtitle,
          hit.authorName,
          if (hit.createdAt != null) l.ago(hit.createdAt!),
        ]),
      );
    case SearchCat.projects:
      return SearchEntry(
        cat: cat,
        key: 'p-${hit.id}',
        title: hit.title,
        keys: hit.title.toLowerCase(),
        subtitle: l.t('search.sub.project', {
          'open': '${hit.openCount ?? 0}',
          'done': '${hit.doneCount ?? 0}',
          'members': '${hit.memberNames.length}',
        }),
        keyChipText: hit.projectKey,
        keyChipColor: hit.projectColor != null
            ? colorFromHex(hit.projectColor!)
            : null,
        memberNames: hit.memberNames,
        archived: hit.archived,
        onSelect: open,
      );
    case SearchCat.teams:
      return entry(
        prefix: 't',
        icon: teamIcon(hit.icon ?? 'hexagon'),
        color: hit.hue == null ? null : teamHueColor(hit.hue!),
        subtitle: joined([hit.key, hit.subtitle]),
      );
    case SearchCat.people:
      return SearchEntry(
        cat: cat,
        key: 'u-${hit.id}',
        title: hit.title,
        keys: '${hit.title} ${hit.username ?? ''}'.toLowerCase(),
        subtitle: joined([
          if (hit.username != null) '@${hit.username}',
          hit.subtitle,
        ]),
        avatarName: hit.title,
        avatarUrl: hit.avatarUrl,
        // The profile slides in over the page the palette was opened on; a
        // server before revision 2 still links to the admin area.
        onSelect: hit.route.startsWith('$peopleRoute/')
            ? (context) => unawaited(openPersonProfile(context, hit.id))
            : open,
      );
    case SearchCat.boards:
      return entry(
        prefix: 'b',
        icon: hit.kind == 'SPRINT' ? LucideIcons.zap : LucideIcons.columns3,
        subtitle: hit.subtitle,
      );
    case SearchCat.docs:
      if (hit.kind == 'SPACE') {
        return entry(
          prefix: 's',
          icon: LucideIcons.library,
          color: hit.hue == null ? null : teamHueColor(hit.hue!),
          subtitle: joined([l.t('search.sub.space'), hit.subtitle]),
        );
      }
      return entry(
        prefix: 'k',
        icon: LucideIcons.fileText,
        subtitle: joined([
          hit.space ?? l.t('search.sub.knowledge'),
          if (hit.updatedAt != null) l.ago(hit.updatedAt!),
        ]),
      );
    case SearchCat.attachments:
      return entry(
        prefix: 'a',
        icon: _attachmentIcon(hit.contentType),
        subtitle: joined([
          hit.readableId,
          hit.subtitle,
          if (hit.size != null) formatBytes(hit.size!),
        ]),
      );
    case SearchCat.shifts:
      final isShift = hit.kind == 'SHIFT';
      return entry(
        prefix: isShift ? 'sh' : 'ev',
        icon: isShift ? LucideIcons.clock : LucideIcons.calendarDays,
        muted: hit.cancelled,
        subtitle: joined([
          if (hit.cancelled) l.t('search.sub.cancelled'),
          if (isShift) hit.subtitle,
          if (hit.startsAt != null) l.moment(hit.startsAt!, hit.endsAt),
          hit.location,
          hit.projectName,
        ]),
      );
    case SearchCat.time:
      if (hit.kind == 'TIMESHEET') {
        return entry(
          prefix: 'ts',
          icon: LucideIcons.table,
          subtitle: joined([
            l.t('search.sub.timesheet'),
            if (hit.from != null) l.days(hit.from!, hit.to),
            if (hit.status != null)
              l.t('time.approval.status.${hit.status!.toLowerCase()}'),
          ]),
        );
      }
      return entry(
        prefix: 'te',
        icon: LucideIcons.clock,
        subtitle: joined([
          if (hit.from != null) l.day(hit.from!),
          if (hit.minutes != null) l.duration(hit.minutes!),
          hit.projectName,
        ]),
      );
    case SearchCat.absences:
      final color = hit.hue == null ? null : teamHueColor(hit.hue!);
      if (hit.kind == 'TYPE') {
        return entry(
          prefix: 'at',
          icon: LucideIcons.calendarPlus,
          color: color,
          subtitle: l.t('search.sub.askAbsence'),
        );
      }
      return entry(
        prefix: 'ar',
        icon: LucideIcons.calendarOff,
        color: color,
        subtitle: joined([
          if (hit.from != null) l.days(hit.from!, hit.to),
          if (hit.status != null)
            l.t('absence.request.status.${hit.status!.toLowerCase()}'),
          hit.subtitle,
        ]),
      );
    case SearchCat.billing:
      if (hit.kind == 'RATE') {
        final amount = hit.amountCents == null || hit.currency == null
            ? null
            : l.t('billing.rate.perHour', {
                'amount': l.money(hit.amountCents!, hit.currency!),
              });
        return entry(
          prefix: 'r',
          icon: LucideIcons.coins,
          subtitle: joined([
            l.t(
              hit.status == 'COST'
                  ? 'billing.kind.cost'
                  : 'billing.kind.billable',
            ),
            if (hit.type != null) l.t(_rateScopeKey(hit.type!)),
            amount,
            if (hit.from != null) l.days(hit.from!, hit.to),
          ]),
        );
      }
      return entry(
        prefix: 'bu',
        icon: LucideIcons.hourglass,
        subtitle: l.t('search.sub.budget'),
      );
    case SearchCat.commands:
      return entry(prefix: 'x');
  }
}

IconData _attachmentIcon(String? contentType) {
  final type = contentType ?? '';
  if (type.startsWith('image/')) return LucideIcons.image;
  if (type.startsWith('video/')) return LucideIcons.video;
  if (type.startsWith('audio/')) return LucideIcons.audioLines;
  if (type == 'application/pdf') return LucideIcons.fileText;
  return LucideIcons.file;
}

String _rateScopeKey(String type) => switch (type) {
  'ISSUE' => 'billing.scope.issue',
  'PROJECT_MEMBER' => 'billing.scope.projectMember',
  'USER' => 'billing.scope.user',
  'TEAM' => 'billing.scope.team',
  'DEFAULT' => 'billing.scope.instanceDefault',
  _ => 'billing.scope.project',
};
