import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:cursor_android/main.dart' show buildTheme;
import 'package:cursor_android/ui/cursor_colors.dart';
import 'package:cursor_android/ui/usage_capsule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const UsageSnapshot sample = UsageSnapshot(cursorUsed: 32, otherUsed: 61);

/// Pumps the capsule and lets MaterialApp finish its theme cross-fade, so a
/// brightness change is fully applied before the expectations run.
Future<void> pumpCapsule(
  WidgetTester tester,
  UsageSnapshot? usage, {
  Preferences preferences = const Preferences(),
  VoidCallback? onTap,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(
        body: Center(
          child: UsageCapsule(
            usage: usage,
            preferences: preferences,
            onTap: onTap,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The tint of the marker span in the pool text [label].
Color? markerColor(WidgetTester tester, String label) {
  final Text text = tester.widget<Text>(find.text(label));
  final TextSpan span = text.textSpan! as TextSpan;
  return (span.children!.first as TextSpan).style?.color;
}

/// The label of the [Semantics] wrapping the pool text [label].
String? semanticsLabel(WidgetTester tester, String label) {
  final Semantics semantics = tester.widget<Semantics>(
    find
        .ancestor(of: find.text(label), matching: find.byType(Semantics))
        .first,
  );
  return semantics.properties.label;
}

void main() {
  group('usageValue', () {
    test('formats remaining, used, unlimited and unknown values', () {
      expect(usageValue(sample, cursor: true, remaining: true), '68%');
      expect(usageValue(sample, cursor: false, remaining: true), '39%');
      expect(usageValue(sample, cursor: true, remaining: false), '32%');
      expect(
        usageValue(
          const UsageSnapshot(cursorUsed: 32.7),
          cursor: true,
          remaining: true,
        ),
        '67%',
      );
      expect(
        usageValue(
          const UsageSnapshot(unlimited: true),
          cursor: true,
          remaining: true,
        ),
        '∞',
      );
      expect(usageValue(null, cursor: true, remaining: true), '—');
      expect(
        usageValue(
          const UsageSnapshot(cursorUsed: 32),
          cursor: false,
          remaining: true,
        ),
        '—',
      );
    });
  });

  testWidgets('shows both pools from a snapshot', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpCapsule(tester, sample);
    expect(find.text('● Cursor 68%'), findsOneWidget);
    expect(find.text('○ Other 39%'), findsOneWidget);
    expect(find.text('remaining'), findsOneWidget);
    expect(
      semanticsLabel(tester, '● Cursor 68%'),
      'Cursor Model 68% remaining',
    );
    expect(semanticsLabel(tester, '○ Other 39%'), 'Other Model 39% remaining');
    expect(
      find.bySemanticsLabel(RegExp('Cursor Model 68% remaining')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('used mode shows used values', (WidgetTester tester) async {
    await pumpCapsule(
      tester,
      sample,
      preferences: const Preferences(remaining: false),
    );
    expect(find.text('● Cursor 32%'), findsOneWidget);
    expect(find.text('○ Other 61%'), findsOneWidget);
    expect(find.text('used'), findsOneWidget);
  });

  testWidgets('unlimited shows infinity', (WidgetTester tester) async {
    await pumpCapsule(tester, const UsageSnapshot(unlimited: true));
    expect(find.text('● Cursor ∞'), findsOneWidget);
    expect(find.text('○ Other ∞'), findsOneWidget);
  });

  testWidgets('missing usage shows a dash', (WidgetTester tester) async {
    await pumpCapsule(tester, null);
    expect(find.text('● Cursor —'), findsOneWidget);
    expect(find.text('○ Other —'), findsOneWidget);
  });

  testWidgets('hidden pools are not rendered', (WidgetTester tester) async {
    await pumpCapsule(
      tester,
      sample,
      preferences: const Preferences(cursor: false),
    );
    expect(find.textContaining('Cursor'), findsNothing);
    expect(find.text('○ Other 39%'), findsOneWidget);

    await pumpCapsule(
      tester,
      sample,
      preferences: const Preferences(cursor: false, other: false),
    );
    expect(find.byType(Text), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(tester.getSize(find.byType(UsageCapsule)), Size.zero);
  });

  testWidgets('tapping calls onTap', (WidgetTester tester) async {
    int taps = 0;
    await pumpCapsule(tester, sample, onTap: () => taps++);
    await tester.tap(find.byType(UsageCapsule));
    expect(taps, 1);
  });

  testWidgets('only the markers use the pool colors', (
    WidgetTester tester,
  ) async {
    await pumpCapsule(tester, sample);
    expect(markerColor(tester, '● Cursor 68%'), poolCursor);
    expect(markerColor(tester, '○ Other 39%'), poolOtherLight);
    final Text text = tester.widget<Text>(find.text('● Cursor 68%'));
    final BuildContext context = tester.element(find.byType(UsageCapsule));
    expect(text.style?.color, Theme.of(context).colorScheme.onSurface);

    await pumpCapsule(tester, sample, brightness: Brightness.dark);
    expect(markerColor(tester, '● Cursor 68%'), poolCursor);
    expect(markerColor(tester, '○ Other 39%'), poolOtherDark);
  });

  test('pool colors follow the brightness', () {
    expect(poolCursorColor(Brightness.light), poolCursor);
    expect(poolCursorColor(Brightness.dark), poolCursor);
    expect(poolOtherColor(Brightness.light), const Color(0xFF82817C));
    expect(poolOtherColor(Brightness.dark), const Color(0xFF767470));
  });

  test('preferences default to Kotlin values', () {
    const Preferences preferences = Preferences();
    expect(preferences.remaining, isTrue);
    expect(preferences.cursor, isTrue);
    expect(preferences.other, isTrue);
    expect(preferences.pace, isTrue);
    expect(preferences.paused, isFalse);
    expect(preferences.intervalSeconds, 60);
    expect(preferences.language, 'en');
    expect(preferences.copyWith(cursor: false).cursor, isFalse);
    expect(preferences.copyWith(cursor: false).other, isTrue);
  });
}
