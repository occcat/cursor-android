import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:cursor_android/main.dart' show buildTheme;
import 'package:cursor_android/ui/cursor_colors.dart';
import 'package:cursor_android/ui/usage_panel.dart';
import 'package:cursor_android/ui/usage_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const int day = UsageSnapshot.day;
const UsageSnapshot sample = UsageSnapshot(
  cursorUsed: 32,
  otherUsed: 61,
  fetchedAt: 1000,
);
const String connectMessage =
    'Connect a web session in Settings to view usage.';

/// Pumps the panel and lets MaterialApp finish any theme transition.
Future<void> pumpPanel(
  WidgetTester tester,
  UsageSnapshot? usage, {
  Preferences preferences = const Preferences(),
  bool connected = true,
  VoidCallback? onRefresh,
  int nowMs = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: UsagePanel(
          usage: usage,
          preferences: preferences,
          connected: connected,
          onRefresh: onRefresh,
          nowMs: nowMs,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FilledButton refreshButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Refresh usage'),
);

void main() {
  testWidgets('disconnected shows the connect message and disables Refresh', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await pumpPanel(tester, null, connected: false, onRefresh: () => taps++);
    expect(find.text('Cursor Usage'), findsOneWidget);
    expect(find.text(connectMessage), findsOneWidget);
    expect(refreshButton(tester).enabled, isFalse);
    await tester.ensureVisible(find.text('Refresh usage'));
    await tester.tap(find.text('Refresh usage'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('connected shows both pools with bars', (
    WidgetTester tester,
  ) async {
    await pumpPanel(tester, sample);
    expect(
      find.text('Account quota · last successful snapshot'),
      findsOneWidget,
    );
    expect(find.text(connectMessage), findsNothing);
    expect(find.text('Cursor Model'), findsOneWidget);
    expect(find.text('Other Model'), findsOneWidget);
    expect(find.text('68%'), findsOneWidget);
    expect(find.text('39%'), findsOneWidget);
    expect(find.text('Remaining'), findsNWidgets(2));
    final List<UsageProgress> bars = tester
        .widgetList<UsageProgress>(find.byType(UsageProgress))
        .toList();
    expect(bars, hasLength(2));
    expect(bars[0].fraction, closeTo(0.68, 1e-9));
    expect(bars[0].color, poolCursor);
    expect(bars[1].fraction, closeTo(0.39, 1e-9));
    expect(bars[1].color, poolOtherLight);
    expect(find.byType(UsageDot), findsNWidgets(2));
    expect(find.byType(Divider), findsOneWidget);
    expect(find.textContaining('Updated '), findsOneWidget);
    expect(find.textContaining('Resets '), findsNothing);
    expect(refreshButton(tester).enabled, isTrue);
  });

  testWidgets('used mode shows used values', (WidgetTester tester) async {
    await pumpPanel(
      tester,
      sample,
      preferences: const Preferences(remaining: false),
    );
    expect(find.text('32%'), findsOneWidget);
    expect(find.text('61%'), findsOneWidget);
    expect(find.text('Used'), findsNWidgets(2));
    final UsageProgress bar = tester.widget<UsageProgress>(
      find.byType(UsageProgress).first,
    );
    expect(bar.fraction, closeTo(0.32, 1e-9));
  });

  testWidgets('unlimited shows infinity without bars or reset', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      const UsageSnapshot(unlimited: true, cycleEnd: 30 * day),
      nowMs: 40 * day,
    );
    expect(find.text('∞'), findsNWidgets(2));
    expect(find.byType(UsageProgress), findsNothing);
    expect(find.textContaining('Resets '), findsNothing);
    expect(find.text('Awaiting new billing cycle data'), findsNothing);
  });

  testWidgets('unknown usage shows dashes and no snapshot footer', (
    WidgetTester tester,
  ) async {
    await pumpPanel(tester, null);
    expect(find.text('—'), findsNWidgets(2));
    expect(find.byType(UsageProgress), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(find.textContaining('Updated '), findsNothing);
  });

  testWidgets('a missing pool shows a dash and a hidden pool is omitted', (
    WidgetTester tester,
  ) async {
    await pumpPanel(tester, const UsageSnapshot(cursorUsed: 32));
    expect(find.text('68%'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(UsageProgress), findsOneWidget);

    await pumpPanel(
      tester,
      sample,
      preferences: const Preferences(other: false),
    );
    expect(find.text('Cursor Model'), findsOneWidget);
    expect(find.text('Other Model'), findsNothing);
    expect(find.text('39%'), findsNothing);
    expect(find.byType(UsageProgress), findsOneWidget);
  });

  testWidgets('an expired cycle shows the pending reset notice', (
    WidgetTester tester,
  ) async {
    await pumpPanel(
      tester,
      const UsageSnapshot(cursorUsed: 32, cycleStart: 0, cycleEnd: 30 * day),
      nowMs: 31 * day,
    );
    expect(find.text('Awaiting new billing cycle data'), findsOneWidget);
    expect(
      find.text('Resets ${formatUsageTime(30 * day)}'),
      findsOneWidget,
    );
    expect(find.text('68%'), findsOneWidget);
    expect(find.textContaining('pace'), findsNothing);
  });

  testWidgets('paused shows the paused notice', (WidgetTester tester) async {
    await pumpPanel(tester, sample);
    expect(find.text('Automatic refresh paused'), findsNothing);
    await pumpPanel(
      tester,
      sample,
      preferences: const Preferences(paused: true),
    );
    expect(find.text('Automatic refresh paused'), findsOneWidget);
  });

  testWidgets('Refresh calls onRefresh when connected', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await pumpPanel(tester, sample, onRefresh: () => taps++);
    await tester.ensureVisible(find.text('Refresh usage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh usage'));
    expect(taps, 1);
  });

  testWidgets('pace notes use raw used against the billing day target', (
    WidgetTester tester,
  ) async {
    final int start = DateTime.utc(2026, 10, 1, 12).millisecondsSinceEpoch;
    final UsageSnapshot usage = UsageSnapshot(
      cursorUsed: 50,
      otherUsed: 1,
      cycleStart: start,
      cycleEnd: start + 30 * day,
    );
    final int now = start + 9 * day;
    await pumpPanel(tester, usage, nowMs: now);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('99%'), findsOneWidget);
    expect(find.text('Faster than billing pace'), findsOneWidget);
    expect(find.text('Slower than billing pace'), findsOneWidget);
    expect(
      find.text('Resets ${formatUsageTime(start + 30 * day)}'),
      findsOneWidget,
    );

    await pumpPanel(
      tester,
      usage,
      preferences: const Preferences(pace: false),
      nowMs: now,
    );
    expect(find.textContaining('pace'), findsNothing);
  });

  testWidgets('an estimated cycle is marked on the pace note', (
    WidgetTester tester,
  ) async {
    final int end = DateTime.utc(2024, 3, 31, 12).millisecondsSinceEpoch;
    final int now = DateTime.utc(2024, 2, 29, 12).millisecondsSinceEpoch;
    await pumpPanel(
      tester,
      UsageSnapshot(cursorUsed: 3, cycleEnd: end),
      preferences: const Preferences(other: false),
      nowMs: now,
    );
    expect(find.text('On pace · estimated cycle'), findsOneWidget);
  });

  test('formatUsageTime prints local date and minutes', () {
    final int time = DateTime(2026, 10, 21, 9, 5).millisecondsSinceEpoch;
    expect(formatUsageTime(time), '2026-10-21 09:05');
  });

  testWidgets('UsageProgress clamps its fill and UsageDot is 6 dp', (
    WidgetTester tester,
  ) async {
    expect(
      const UsageProgress(value: 1.5, color: poolCursor).fraction,
      1.0,
    );
    expect(
      const UsageProgress(value: -1, color: poolCursor).fraction,
      0.0,
    );
    expect(
      const UsageProgress(value: double.nan, color: poolCursor).fraction,
      0.0,
    );
    expect(usageTrackColor(Brightness.light), usageTrackLight);
    expect(usageTrackColor(Brightness.dark), usageTrackDark);
    await tester.pumpWidget(
      const Center(child: UsageDot(color: poolCursor)),
    );
    expect(tester.getSize(find.byType(UsageDot)), const Size(6, 6));
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 200,
            child: UsageProgress(
              value: 0.25,
              color: poolCursor,
              trackColor: usageTrackLight,
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(UsageProgress)), const Size(200, 6));
    expect(
      tester.getSize(find.byType(FractionallySizedBox)),
      const Size(50, 6),
    );
  });
}
