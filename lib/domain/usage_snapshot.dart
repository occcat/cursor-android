/// Usage pools and billing-cycle pace, ported from Kotlin 0.1.5 `Usage.kt`.
library;

import 'dart:math' as math;

/// One usage reading: the Cursor (auto) and other (API) pools as percent
/// used, plus the billing cycle as epoch milliseconds.
class UsageSnapshot {
  const UsageSnapshot({
    this.cursorUsed,
    this.otherUsed,
    this.cycleStart,
    this.cycleEnd,
    this.unlimited = false,
    this.membership,
    this.fetchedAt = 0,
  });

  /// Reads `/api/usage-summary`-style JSON fetched at [nowMs].
  factory UsageSnapshot.fromJson(Map<String, dynamic> root, int nowMs) {
    final Object? usage = root['individualUsage'];
    final Object? plan = usage is Map ? usage['plan'] : null;
    final Map<Object?, Object?>? pools = plan is Map ? plan : null;
    final Object? unlimited = root['isUnlimited'];
    return UsageSnapshot(
      cursorUsed: percent(pools?['autoPercentUsed']),
      otherUsed: percent(pools?['apiPercentUsed']),
      cycleStart: _timestamp(root['billingCycleStart']),
      cycleEnd: _timestamp(root['billingCycleEnd']),
      unlimited: unlimited == true || unlimited == 'true',
      membership: _content(root['membershipType']),
      fetchedAt: nowMs,
    );
  }

  /// One day in milliseconds.
  static const int day = 86400000;

  /// Percent of the Cursor pool used, as reported (not clamped).
  final double? cursorUsed;

  /// Percent of the other pool used, as reported (not clamped).
  final double? otherUsed;

  final int? cycleStart;
  final int? cycleEnd;
  final bool unlimited;
  final String? membership;

  /// When this snapshot was fetched, in epoch milliseconds.
  final int fetchedAt;

  static final RegExp _decimal = RegExp(
    r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$',
  );

  /// Display value for one pool: used, or `100 - used` when [remaining].
  ///
  /// Only this value is clamped to `0..100`; the stored fields are not.
  double? value({required bool cursor, required bool remaining}) {
    final double? raw = cursor ? cursorUsed : otherUsed;
    if (raw == null) {
      return null;
    }
    final double used = raw.clamp(0.0, 100.0).toDouble();
    return remaining ? 100.0 - used : used;
  }

  /// Whether the cycle has ended but the server has not reported a new one.
  bool pendingReset(int nowMs) {
    final int? end = cycleEnd;
    return !unlimited && end != null && nowMs >= end;
  }

  /// Where usage should be at the end of today's billing day, or `null` when
  /// unlimited, without a cycle end, or outside the cycle.
  ///
  /// A start missing or not 1 to 32 days before the end is replaced by the
  /// same instant one calendar month earlier (UTC), and marked as estimated.
  Pace? pace(int nowMs) {
    if (unlimited) {
      return null;
    }
    final int? end = cycleEnd;
    if (end == null) {
      return null;
    }
    final int? given = cycleStart;
    final int? validStart =
        given != null && end - given >= day && end - given <= 32 * day
        ? given
        : null;
    final int? start = validStart ?? _previousMonth(end);
    if (start == null || nowMs < start || nowMs >= end || end <= start) {
      return null;
    }
    final double elapsedDays = ((nowMs - start) / day).floorToDouble();
    final double fraction = ((elapsedDays + 1) * day / (end - start))
        .clamp(0.0, 1.0)
        .toDouble();
    return Pace(fraction * 100.0, estimated: validStart == null);
  }

  /// A finite percent from a plain decimal number or numeric string.
  ///
  /// Booleans, `NaN`, `Infinity`, whitespace, suffixes, hex and exponents in
  /// strings all give `null`, so an unknown value is never shown as zero.
  static double? percent(Object? element) {
    final String? text = element is String
        ? element
        : element is num
        ? '$element'
        : null;
    if (text == null || !_decimal.hasMatch(text)) {
      return null;
    }
    final double? value = double.tryParse(
      text.endsWith('.') ? '${text}0' : text,
    );
    return value != null && value.isFinite ? value : null;
  }
}

/// Target usage for today and whether the cycle start was estimated.
class Pace {
  const Pace(this.targetUsed, {required this.estimated});

  /// Percent used that would be exactly on pace at the end of today.
  final double targetUsed;

  /// Whether the cycle start was estimated from the end.
  final bool estimated;

  /// `1` when more than 5 points ahead, `-1` when more than 5 behind, else 0.
  int category(double used) {
    if (used - targetUsed > 5) {
      return 1;
    }
    if (used - targetUsed < -5) {
      return -1;
    }
    return 0;
  }
}

/// Text of a JSON scalar, like Kotlin's `JsonPrimitive.contentOrNull`.
String? _content(Object? value) =>
    value is String || value is num || value is bool ? '$value' : null;

final RegExp _instant = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?'
  r'(?:(Z)|([+-])(\d{2}):(\d{2}))$',
);

/// Epoch milliseconds of an ISO-8601 instant such as
/// `2026-10-01T12:00:00Z` or `2026-10-01T13:00:00.5+01:00`.
///
/// Out-of-range fields are rejected instead of rolling over, like
/// `Instant.parse`.
int? _timestamp(Object? value) {
  if (value is! String) {
    return null;
  }
  final RegExpMatch? match = _instant.firstMatch(value);
  if (match == null) {
    return null;
  }
  int field(int group) => int.parse(match.group(group) ?? '0');
  final int year = field(1);
  final int month = field(2);
  final int dayOfMonth = field(3);
  final int hour = field(4);
  final int minute = field(5);
  final int second = field(6);
  if (month < 1 ||
      month > 12 ||
      dayOfMonth < 1 ||
      dayOfMonth > _daysIn(year, month) ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final String fraction = (match.group(7) ?? '').padRight(3, '0');
  int offsetMinutes = 0;
  if (match.group(8) == null) {
    final int offsetHours = field(10);
    final int offsetRest = field(11);
    if (offsetHours > 18 || offsetRest > 59) {
      return null;
    }
    offsetMinutes = offsetHours * 60 + offsetRest;
    if (match.group(9) == '-') {
      offsetMinutes = -offsetMinutes;
    }
  }
  final int local = DateTime.utc(
    year,
    month,
    dayOfMonth,
    hour,
    minute,
    second,
    int.parse(fraction.substring(0, 3)),
  ).millisecondsSinceEpoch;
  return local - offsetMinutes * 60000;
}

/// [epochMs] minus one calendar month in UTC, clamping the day of month.
int? _previousMonth(int epochMs) {
  if (epochMs.abs() > 8640000000000000) {
    return null;
  }
  final DateTime end = DateTime.fromMillisecondsSinceEpoch(
    epochMs,
    isUtc: true,
  );
  final int year = end.month == 1 ? end.year - 1 : end.year;
  final int month = end.month == 1 ? 12 : end.month - 1;
  return DateTime.utc(
    year,
    month,
    math.min(end.day, _daysIn(year, month)),
    end.hour,
    end.minute,
    end.second,
    end.millisecond,
    end.microsecond,
  ).millisecondsSinceEpoch;
}

int _daysIn(int year, int month) => DateTime.utc(year, month + 1, 0).day;
