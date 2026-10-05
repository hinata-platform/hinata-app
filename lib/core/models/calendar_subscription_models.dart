import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

import '../util/dates.dart';

/// What the last fetch of a subscribed calendar came to (HIN-94).
enum CalendarSubscriptionStatus {
  /// Added, not read yet.
  pending,

  /// A read is running.
  running,
  ok,

  /// Read, but the shown period held more events than are kept.
  truncated,
  failed,

  /// Five failures in a row: no longer read on schedule until switched back on.
  paused;

  static CalendarSubscriptionStatus parse(Object? value) => switch (value) {
    'RUNNING' => running,
    'OK' => ok,
    'TRUNCATED' => truncated,
    'FAILED' => failed,
    'PAUSED' => paused,
    _ => pending,
  };

  /// Whether the status is something the person has to look at.
  bool get isProblem => this == failed || this == paused || this == truncated;
}

/// The rule "take ended events of this calendar over as entries".
class CalendarTakeoverRule extends Equatable {
  const CalendarTakeoverRule({
    this.enabled = false,
    this.projectId,
    this.tags = const [],
    this.billable,
    this.since,
  });

  static const off = CalendarTakeoverRule();

  final bool enabled;
  final String? projectId;
  final List<String> tags;
  final bool? billable;

  /// Only events starting after this are taken over; set when the rule is switched on.
  final DateTime? since;

  factory CalendarTakeoverRule.fromJson(Map<String, dynamic>? json) {
    if (json == null) return off;
    return CalendarTakeoverRule(
      enabled: json['enabled'] as bool? ?? false,
      projectId: json['projectId'] as String?,
      tags: [
        for (final tag in (json['tags'] as List<dynamic>?) ?? const [])
          if (tag is String) tag,
      ],
      billable: json['billable'] as bool?,
      since: parseInstant(json['since']),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'projectId': ?projectId,
    'tags': tags,
    'billable': ?billable,
  };

  @override
  List<Object?> get props => [enabled, projectId, tags, billable, since];
}

/// An event the rule could not take over, with the refusal as a message key.
class CalendarTakeoverSkip extends Equatable {
  const CalendarTakeoverSkip({
    required this.startsAt,
    required this.messageKey,
    this.message,
    this.eventId,
  });

  final String? eventId;
  final DateTime? startsAt;
  final String messageKey;

  /// [messageKey] in the reader's language, as the server put it.
  final String? message;

  factory CalendarTakeoverSkip.fromJson(Map<String, dynamic> json) =>
      CalendarTakeoverSkip(
        eventId: json['eventId'] as String?,
        startsAt: parseInstant(json['startsAt']),
        messageKey: json['messageKey'] as String? ?? 'errors.unexpected',
        message: json['message'] as String?,
      );

  @override
  List<Object?> get props => [eventId, startsAt, messageKey, message];
}

/// One of the reader's own calendar subscriptions. The address never comes
/// back from the server; [hostMasked] stands in for it.
class CalendarSubscription extends Equatable {
  const CalendarSubscription({
    required this.id,
    required this.name,
    required this.color,
    this.hostMasked,
    this.enabled = true,
    this.rule = CalendarTakeoverRule.off,
    this.status = CalendarSubscriptionStatus.pending,
    this.lastError,
    this.lastErrorArg,
    this.lastErrorMessage,
    this.lastFetchedAt,
    this.eventCount = 0,
    this.skips = const [],
  });

  final String id;
  final String name;

  /// `#RRGGBB`.
  final String color;
  final String? hostMasked;
  final bool enabled;
  final CalendarTakeoverRule rule;
  final CalendarSubscriptionStatus status;

  /// A message key, with [lastErrorArg] as its argument.
  final String? lastError;
  final int? lastErrorArg;

  /// The last failure in the reader's language, as the server put it.
  final String? lastErrorMessage;
  final DateTime? lastFetchedAt;
  final int eventCount;
  final List<CalendarTakeoverSkip> skips;

  Color get swatch => calendarColor(color);

  factory CalendarSubscription.fromJson(Map<String, dynamic> json) =>
      CalendarSubscription(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        color: json['color'] as String? ?? calendarColorChoices.first,
        hostMasked: json['hostMasked'] as String?,
        enabled: json['enabled'] as bool? ?? true,
        rule: CalendarTakeoverRule.fromJson(
          json['autoConvert'] as Map<String, dynamic>?,
        ),
        status: CalendarSubscriptionStatus.parse(json['status']),
        lastError: json['lastError'] as String?,
        lastErrorArg: (json['lastErrorArg'] as num?)?.toInt(),
        lastErrorMessage: json['lastErrorMessage'] as String?,
        lastFetchedAt: parseInstant(json['lastFetchedAt']),
        eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
        skips: [
          for (final skip in (json['skips'] as List<dynamic>?) ?? const [])
            if (skip is Map<String, dynamic>)
              CalendarTakeoverSkip.fromJson(skip),
        ],
      );

  @override
  List<Object?> get props => [
    id,
    name,
    color,
    hostMasked,
    enabled,
    rule,
    status,
    lastError,
    lastErrorArg,
    lastErrorMessage,
    lastFetchedAt,
    eventCount,
    skips,
  ];
}

/// What the person sends to add or change a subscription. [url] is only sent
/// when it was typed: an edit that leaves it empty keeps the stored address.
class CalendarSubscriptionDraft extends Equatable {
  const CalendarSubscriptionDraft({
    required this.name,
    required this.color,
    this.url,
    this.enabled,
    this.rule,
  });

  final String name;
  final String color;
  final String? url;
  final bool? enabled;
  final CalendarTakeoverRule? rule;

  Map<String, dynamic> toJson() => {
    'name': name,
    'color': color,
    if (url != null && url!.trim().isNotEmpty) 'url': url!.trim(),
    'enabled': ?enabled,
    if (rule != null) 'autoConvert': rule!.toJson(),
  };

  @override
  List<Object?> get props => [name, color, url, enabled, rule];
}

/// One event of the reader's subscriptions in the calendar window: a
/// suggestion, not an entry. An all-day event runs midnight to midnight.
class CalendarEventSuggestion extends Equatable {
  const CalendarEventSuggestion({
    required this.id,
    required this.subscriptionId,
    required this.start,
    required this.end,
    this.color,
    this.allDay = false,
    this.free = false,
    this.tentative = false,
    this.summary,
    this.location,
    this.convertedEntryId,
  });

  final String id;
  final String subscriptionId;
  final DateTime start;
  final DateTime end;

  /// The subscription's colour, `#RRGGBB`.
  final String? color;
  final bool allDay;
  final bool free;
  final bool tentative;
  final String? summary;
  final String? location;

  /// The entry taken over from this event, if there is one.
  final String? convertedEntryId;

  bool get converted => convertedEntryId != null;

  Color get swatch => calendarColor(color ?? calendarColorChoices.first);

  int get minutes => end.difference(start).inMinutes;

  /// Whether it can become an entry at all: timed, and between a minute and a day.
  bool get convertible => !allDay && minutes >= 1 && minutes <= 24 * 60;

  static CalendarEventSuggestion? fromJson(Map<String, dynamic> json) {
    final start = parseInstant(json['startsAt']);
    final end = parseInstant(json['endsAt']);
    final id = json['id'] as String?;
    if (start == null || end == null || id == null) return null;
    return CalendarEventSuggestion(
      id: id,
      subscriptionId: json['subscriptionId'] as String? ?? '',
      start: start,
      end: end,
      color: json['color'] as String?,
      allDay: json['allDay'] as bool? ?? false,
      free: json['free'] as bool? ?? false,
      tentative: json['status'] == 'TENTATIVE',
      summary: json['summary'] as String?,
      location: json['location'] as String?,
      convertedEntryId: json['convertedEntryId'] as String?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    subscriptionId,
    start,
    end,
    color,
    allDay,
    free,
    tentative,
    summary,
    location,
    convertedEntryId,
  ];
}

/// What the person chose when taking an event over.
class CalendarConversion extends Equatable {
  const CalendarConversion({
    this.projectId,
    this.issueId,
    this.tags = const [],
    this.billable,
    this.description,
  });

  final String? projectId;
  final String? issueId;
  final List<String> tags;
  final bool? billable;
  final String? description;

  Map<String, dynamic> toJson() => {
    'projectId': ?projectId,
    'issueId': ?issueId,
    'tags': tags,
    'billable': ?billable,
    'description': ?description,
  };

  @override
  List<Object?> get props => [projectId, issueId, tags, billable, description];
}

/// The colours a subscription can take. Fixed, so each one is measured against
/// both themes once rather than whatever a person picks: every one clears 3:1
/// on the light and the dark canvas, which the dashed outline of a suggested
/// block needs (measured 2026-10-05, between 3.43:1 and 4.92:1).
const calendarColorChoices = [
  '#4F7DD9',
  '#27897C',
  '#BF6D1E',
  '#B4549B',
  '#6B8E23',
  '#C0504D',
];

/// [hex] as a colour; the first choice for anything unreadable.
Color calendarColor(String hex) {
  final digits = hex.startsWith('#') ? hex.substring(1) : hex;
  final value = int.tryParse(digits, radix: 16);
  if (digits.length != 6 || value == null) {
    return calendarColor(calendarColorChoices.first);
  }
  return Color(0xFF000000 | value);
}
