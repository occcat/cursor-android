import 'dart:convert';

import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

int instant(String iso) => DateTime.parse(iso).millisecondsSinceEpoch;

void main() {
  const int day = UsageSnapshot.day;

  test('exact pools and numeric strings remain independent', () {
    final Map<String, dynamic> json =
        jsonDecode('''{
      "individualUsage":{"plan":{"autoPercentUsed":"32","apiPercentUsed":61,
      "used":999999,"limit":1}},"isUnlimited":false
    }''')
            as Map<String, dynamic>;
    final UsageSnapshot usage = UsageSnapshot.fromJson(json, 42);
    expect(usage.value(cursor: true, remaining: true), 68.0);
    expect(usage.value(cursor: false, remaining: true), 39.0);
    expect(usage.value(cursor: true, remaining: false), 32.0);
    expect(usage.fetchedAt, 42);
  });

  test('invalid percent is unknown rather than zero', () {
    for (final String text in <String>[
      '',
      'NaN',
      'Infinity',
      'true',
      ' 2',
      '3%',
      '0x20',
      '1e4',
    ]) {
      expect(UsageSnapshot.percent(text), isNull, reason: text);
    }
    expect(UsageSnapshot.percent(true), isNull);
    expect(UsageSnapshot.percent(null), isNull);
    expect(UsageSnapshot.percent(<String, dynamic>{}), isNull);
    expect(UsageSnapshot.percent('1${'0' * 400}'), isNull);
    expect(UsageSnapshot.percent('+12.5'), 12.5);
    expect(UsageSnapshot.percent('5.'), 5.0);
    expect(UsageSnapshot.percent('.5'), 0.5);
    expect(UsageSnapshot.percent(-3), -3.0);
  });

  test('partial usage keeps the missing slot and clamps display only', () {
    const UsageSnapshot usage = UsageSnapshot(cursorUsed: 130);
    expect(usage.value(cursor: true, remaining: true), 0.0);
    expect(usage.cursorUsed, 130.0);
    expect(usage.value(cursor: false, remaining: true), isNull);
  });

  test('unlimited has no pace or reset warning', () {
    const UsageSnapshot usage = UsageSnapshot(unlimited: true, cycleEnd: 10);
    expect(usage.pace(20), isNull);
    expect(usage.pendingReset(20), isFalse);
  });

  test('pace targets the billing day end and the threshold is strict', () {
    final int start = instant('2026-10-01T12:00:00Z');
    final UsageSnapshot usage = UsageSnapshot(
      cycleStart: start,
      cycleEnd: start + 30 * day,
    );
    final Pace pace = usage.pace(start)!;
    expect(pace.targetUsed, closeTo(100.0 / 30, 0.0001));
    expect(pace.estimated, isFalse);
    expect(pace.category(pace.targetUsed + 5), 0);
    expect(pace.category(pace.targetUsed + 5.01), 1);
    expect(pace.category(pace.targetUsed - 5.01), -1);
  });

  test('an expired cycle keeps old values until a new cycle arrives', () {
    const UsageSnapshot usage = UsageSnapshot(
      cursorUsed: 32,
      cycleStart: 0,
      cycleEnd: 30 * day,
    );
    expect(usage.pendingReset(31 * day), isTrue);
    expect(usage.value(cursor: true, remaining: true), 68.0);
    expect(usage.pace(31 * day), isNull);
  });

  test('an invalid start uses the previous calendar month as an estimate', () {
    final int end = instant('2024-03-31T12:00:00Z');
    final int now = instant('2024-02-29T12:00:00Z');
    final Pace pace = UsageSnapshot(cycleEnd: end).pace(now)!;
    expect(pace.estimated, isTrue);
    expect(pace.targetUsed, closeTo(100.0 / 31, 0.0001));
    expect(UsageSnapshot(cycleEnd: end).pace(now - 1), isNull);
  });

  test('fromJson reads the cycle, plan flags and membership', () {
    final UsageSnapshot usage = UsageSnapshot.fromJson(<String, dynamic>{
      'billingCycleStart': '2026-10-01T13:00:00.250+01:00',
      'billingCycleEnd': '2026-10-31T12:00:00Z',
      'isUnlimited': true,
      'membershipType': 'pro',
    }, 7);
    expect(usage.cycleStart, instant('2026-10-01T12:00:00.250Z'));
    expect(usage.cycleEnd, instant('2026-10-31T12:00:00Z'));
    expect(usage.unlimited, isTrue);
    expect(usage.membership, 'pro');
    expect(usage.cursorUsed, isNull);
    expect(usage.otherUsed, isNull);
  });

  test('fromJson leaves malformed timestamps unknown', () {
    for (final Object? value in <Object?>[
      '2024-02-30T00:00:00Z',
      '2024-01-01T00:00:00',
      '2024-01-01T00:00Z',
      '2024-01-01 00:00:00Z',
      'soon',
      1700000000000,
      null,
    ]) {
      final UsageSnapshot usage = UsageSnapshot.fromJson(<String, dynamic>{
        'billingCycleEnd': value,
      }, 0);
      expect(usage.cycleEnd, isNull, reason: '$value');
    }
  });
}
