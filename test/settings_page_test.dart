import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/ui/create_agent_page.dart';
import 'package:cursor_android/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const List<CreateAgentOption> environments = <CreateAgentOption>[
  (id: 'env-1', label: 'Linux box'),
];

/// Records every callback the page invokes.
class Calls {
  int connect = 0;
  int disconnect = 0;
  int load = 0;
  int capsule = 0;
  int widgets = 0;
  final List<Preferences> changes = <Preferences>[];
  final List<String> opened = <String>[];

  void onConnectWeb() {
    connect++;
  }

  void onDisconnect() {
    disconnect++;
  }

  void onLoadEnvironments() {
    load++;
  }

  void onCapsule() {
    capsule++;
  }

  void onWidgets() {
    widgets++;
  }

  void onPreferencesChanged(Preferences value) {
    changes.add(value);
  }

  void onOpenEnvironment(String id) {
    opened.add(id);
  }
}

Future<void> pumpPage(
  WidgetTester tester,
  Calls calls, {
  bool webConnected = true,
  bool busy = false,
  bool withPreferences = true,
  bool withHelp = false,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsPage(
          preferences: const Preferences(),
          webConnected: webConnected,
          busy: busy,
          environments: environments,
          onConnectWeb: calls.onConnectWeb,
          onDisconnect: calls.onDisconnect,
          onPreferencesChanged: withPreferences
              ? calls.onPreferencesChanged
              : null,
          onLoadEnvironments: calls.onLoadEnvironments,
          onOpenEnvironment: calls.onOpenEnvironment,
          onOpenFloatingCapsuleHelp: withHelp ? calls.onCapsule : null,
          onOpenWidgetHelp: withHelp ? calls.onWidgets : null,
        ),
      ),
    ),
  );
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder toggle(String label) => find.widgetWithText(SwitchListTile, label);

Finder choice(String label) => find.widgetWithText(ChoiceChip, label);

void main() {
  testWidgets('the web session button follows webConnected', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, webConnected: false);
    expect(find.text('Connect web session'), findsOneWidget);
    expect(find.text('Reconnect web session'), findsNothing);
    expect(find.text('Disconnect & clear local data'), findsNothing);
    await pumpPage(tester, calls);
    expect(find.text('Reconnect web session'), findsOneWidget);
    expect(find.text('Disconnect & clear local data'), findsOneWidget);
    await tapVisible(tester, find.text('Reconnect web session'));
    expect(calls.connect, 1);
  });

  testWidgets('Disconnect asks first; Cancel keeps the session', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    await tapVisible(tester, find.text('Disconnect & clear local data'));
    expect(find.text('Disconnect this device?'), findsOneWidget);
    await tapVisible(tester, find.text('Cancel'));
    expect(find.text('Disconnect this device?'), findsNothing);
    expect(calls.disconnect, 0);
    await tapVisible(tester, find.text('Disconnect & clear local data'));
    await tapVisible(tester, find.text('Disconnect'));
    expect(calls.disconnect, 1);
    expect(find.text('Disconnect this device?'), findsNothing);
  });

  testWidgets('a toggle and chips emit the full copyWith', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    await tapVisible(tester, toggle('Cursor Model'));
    final Preferences cursorOff = calls.changes.last;
    expect(cursorOff.cursor, isFalse);
    expect(cursorOff.other, isTrue);
    expect(cursorOff.remaining, isTrue);
    expect(cursorOff.intervalSeconds, 60);
    expect(cursorOff.language, 'en');
    await tapVisible(tester, choice('120s'));
    expect(calls.changes.last.intervalSeconds, 120);
    expect(calls.changes.last.cursor, isTrue);
    await tapVisible(tester, choice('简体中文'));
    expect(calls.changes.last.language, 'zh-CN');
    expect(calls.changes.last.intervalSeconds, 60);
    expect(calls.changes, hasLength(3));
  });

  testWidgets('every other switch flips its own field', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    await tapVisible(tester, toggle('Other Model'));
    expect(calls.changes.last.other, isFalse);
    await tapVisible(tester, toggle('Show remaining allowance'));
    expect(calls.changes.last.remaining, isFalse);
    await tapVisible(tester, toggle('Billing pace'));
    expect(calls.changes.last.pace, isFalse);
    await tapVisible(tester, toggle('Pause automatic refresh'));
    expect(calls.changes.last.paused, isTrue);
    await tapVisible(tester, toggle('Usage notification'));
    expect(calls.changes.last.notifications, isTrue);
    await tapVisible(tester, toggle('Show agent titles in widgets'));
    expect(calls.changes.last.widgetTitles, isTrue);
    expect(calls.changes.last.cursor, isTrue);
    expect(calls.changes, hasLength(6));
  });

  testWidgets('environments load and open by publicId', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    expect(find.text('CLOUD ENVIRONMENTS'), findsOneWidget);
    await tapVisible(tester, find.text('Load environments'));
    expect(calls.load, 1);
    await tapVisible(tester, find.text('Linux box'));
    expect(calls.opened, <String>['env-1']);
  });

  testWidgets('cloud environments are hidden without a web session', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, webConnected: false);
    expect(find.text('CLOUD ENVIRONMENTS'), findsNothing);
    expect(find.text('Load environments'), findsNothing);
    expect(find.text('Linux box'), findsNothing);
  });

  testWidgets('busy keeps the switches and disables Load environments', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, busy: true);
    expect(find.byType(SwitchListTile), findsNWidgets(7));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Load environments'),
          )
          .onPressed,
      isNull,
    );
    await tapVisible(tester, toggle('Cursor Model'));
    expect(calls.changes.last.cursor, isFalse);
  });

  testWidgets('capsule and widget buttons appear only with callbacks', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    expect(find.text('Start floating capsule'), findsNothing);
    expect(find.text('Add widgets'), findsNothing);
    expect(
      find.textContaining('arrives in a later update'),
      findsOneWidget,
    );
    await pumpPage(tester, calls, withHelp: true);
    await tapVisible(tester, find.text('Start floating capsule'));
    expect(calls.capsule, 1);
    await tapVisible(tester, find.text('Add widgets'));
    expect(calls.widgets, 1);
    expect(find.textContaining('arrives in a later update'), findsNothing);
  });

  testWidgets('switches and chips are disabled without a listener', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, withPreferences: false);
    expect(tester.widget<SwitchListTile>(toggle('Cursor Model')).onChanged,
        isNull);
    expect(tester.widget<ChoiceChip>(choice('60s')).onSelected, isNull);
    expect(calls.changes, isEmpty);
  });
}
