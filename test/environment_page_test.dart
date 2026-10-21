import 'package:cursor_android/ui/environment_page.dart';
import 'package:cursor_android/ui/inbox_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const ValueKey<String> nameKey = ValueKey<String>('environment-name');
const ValueKey<String> jsonKey = ValueKey<String>('environment-json');
const ValueKey<String> secretNameKey = ValueKey<String>(
  'environment-secret-name',
);
const ValueKey<String> secretValueKey = ValueKey<String>(
  'environment-secret-value',
);
final Finder saveButton = find.widgetWithText(FilledButton, 'Save environment');
final Finder addButton = find.widgetWithText(FilledButton, 'Add secret');
final Finder deleteButtons = find.widgetWithText(TextButton, 'Delete');

/// Records every callback the page invokes.
class Calls {
  int refresh = 0;
  final List<(String, String)> saves = <(String, String)>[];
  final List<(String, String)> added = <(String, String)>[];
  final List<(String, String?)> revoked = <(String, String?)>[];

  void onRefresh() {
    refresh++;
  }

  Future<void> onSave(String name, String environmentJson) async {
    saves.add((name, environmentJson));
  }

  Future<void> onAddSecret(String name, String value) async {
    added.add((name, value));
  }

  Future<void> onRevokeSecret(String name, String? id) async {
    revoked.add((name, id));
  }
}

Future<void> pumpPage(
  WidgetTester tester,
  Calls calls, {
  String publicId = 'env-1',
  bool loaded = true,
  bool busy = false,
  String? name = 'Linux box',
  String? environmentJson = '{"install":"npm ci"}',
  List<Map<String, dynamic>> secrets = const <Map<String, dynamic>>[],
  String? errorMessage,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EnvironmentPage(
          publicId: publicId,
          loaded: loaded,
          busy: busy,
          name: name,
          environmentJson: environmentJson,
          secrets: secrets,
          errorMessage: errorMessage,
          onRefresh: calls.onRefresh,
          onSave: calls.onSave,
          onAddSecret: calls.onAddSecret,
          onRevokeSecret: calls.onRevokeSecret,
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

bool enabled(WidgetTester tester, Finder button) =>
    tester.widget<FilledButton>(button).onPressed != null;

String fieldText(WidgetTester tester, ValueKey<String> key) =>
    tester.widget<TextField>(find.byKey(key)).controller!.text;

void main() {
  testWidgets('an unloaded environment shows Loading and Retry', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, loaded: false);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Loading this environment…'), findsOneWidget);
    expect(find.byKey(nameKey), findsNothing);
    expect(saveButton, findsNothing);
    expect(addButton, findsNothing);
    await tapVisible(tester, find.widgetWithText(ActionChip, 'Retry'));
    expect(calls.refresh, 1);
  });

  testWidgets('loaded fields render and Save follows name and busy', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    expect(fieldText(tester, nameKey), 'Linux box');
    expect(fieldText(tester, jsonKey), '{"install":"npm ci"}');
    expect(
      find.text(
        'Saving replaces the full environment configuration. Repositories '
        'and owner stay unchanged.',
      ),
      findsOneWidget,
    );
    expect(enabled(tester, saveButton), isTrue);
    await tester.enterText(find.byKey(nameKey), '   ');
    await tester.pump();
    expect(enabled(tester, saveButton), isFalse);
    await tester.enterText(find.byKey(nameKey), 'Box');
    await tester.pump();
    expect(enabled(tester, saveButton), isTrue);
    await pumpPage(tester, calls, busy: true);
    expect(enabled(tester, saveButton), isFalse);
  });

  testWidgets('invalid JSON blocks the dialog and marks the field', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    for (final String text in <String>['not json', '[1, 2]', '"text"']) {
      await tester.enterText(find.byKey(jsonKey), text);
      await tester.pump();
      await tapVisible(tester, saveButton);
      expect(find.text('Replace configuration?'), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(jsonKey)).decoration!.errorText,
        invalidEnvironmentJson,
      );
    }
    expect(calls.saves, isEmpty);
    await tester.enterText(find.byKey(jsonKey), '{}');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(jsonKey)).decoration!.errorText,
      isNull,
    );
  });

  testWidgets('Cancel dismisses and Confirm saves the trimmed name', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    await tester.enterText(find.byKey(nameKey), '  Box  ');
    await tester.enterText(find.byKey(jsonKey), ' {"a": 1} ');
    await tester.pump();
    await tapVisible(tester, saveButton);
    expect(find.text('Replace configuration?'), findsOneWidget);
    expect(
      find.text('This changes the saved environment for future agents.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Cancel'));
    expect(find.text('Replace configuration?'), findsNothing);
    expect(calls.saves, isEmpty);
    await tapVisible(tester, saveButton);
    await tapVisible(tester, find.text('Confirm'));
    expect(calls.saves, <(String, String)>[('Box', ' {"a": 1} ')]);
    expect(find.text('Replace configuration?'), findsNothing);
  });

  testWidgets('new values are adopted when loaded or publicId changes', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(
      tester,
      calls,
      loaded: false,
      name: null,
      environmentJson: null,
    );
    await pumpPage(tester, calls, name: 'Fresh', environmentJson: '{}');
    expect(fieldText(tester, nameKey), 'Fresh');
    expect(fieldText(tester, jsonKey), '{}');
    await tester.enterText(find.byKey(nameKey), 'Edited');
    await tester.pump();
    await pumpPage(tester, calls, name: 'Fresh', environmentJson: '{}');
    expect(fieldText(tester, nameKey), 'Edited');
    await tester.enterText(find.byKey(secretNameKey), 'TOKEN');
    await pumpPage(
      tester,
      calls,
      publicId: 'env-2',
      name: 'Second',
      environmentJson: '{"b":2}',
    );
    expect(fieldText(tester, nameKey), 'Second');
    expect(fieldText(tester, jsonKey), '{"b":2}');
    expect(fieldText(tester, secretNameKey), isEmpty);
  });

  testWidgets('secrets show name · type and Delete revokes with the id', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(
      tester,
      calls,
      secrets: <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'API_KEY',
          'type': 'runtime_secret',
          'id': 'sec-1',
        },
        <String, dynamic>{'name': 'PLAIN'},
      ],
    );
    expect(find.text('RUNTIME SECRETS'), findsOneWidget);
    expect(
      find.text(
        'Values cannot be read back. New values are sent once and never '
        'cached.',
      ),
      findsOneWidget,
    );
    expect(find.text('API_KEY · runtime_secret'), findsOneWidget);
    expect(find.text('PLAIN'), findsOneWidget);
    expect(deleteButtons, findsNWidgets(2));
    await tapVisible(tester, deleteButtons.first);
    expect(find.text('Revoke secret?'), findsOneWidget);
    expect(find.text('API_KEY'), findsOneWidget);
    await tapVisible(tester, find.text('Cancel'));
    expect(find.text('Revoke secret?'), findsNothing);
    expect(calls.revoked, isEmpty);
    await tapVisible(tester, deleteButtons.first);
    await tapVisible(tester, find.text('Confirm'));
    await tapVisible(tester, deleteButtons.last);
    await tapVisible(tester, find.text('Confirm'));
    expect(calls.revoked, <(String, String?)>[
      ('API_KEY', 'sec-1'),
      ('PLAIN', null),
    ]);
  });

  testWidgets('Add secret needs both fields and clears them after', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    expect(
      tester.widget<TextField>(find.byKey(secretValueKey)).obscureText,
      isTrue,
    );
    expect(enabled(tester, addButton), isFalse);
    await tester.enterText(find.byKey(secretNameKey), '  TOKEN  ');
    await tester.pump();
    expect(enabled(tester, addButton), isFalse);
    await tester.enterText(find.byKey(secretValueKey), '   ');
    await tester.pump();
    expect(enabled(tester, addButton), isFalse);
    await tester.enterText(find.byKey(secretValueKey), ' s3cr3t ');
    await tester.pump();
    expect(enabled(tester, addButton), isTrue);
    await tapVisible(tester, addButton);
    expect(calls.added, <(String, String)>[('TOKEN', ' s3cr3t ')]);
    expect(fieldText(tester, secretNameKey), isEmpty);
    expect(fieldText(tester, secretValueKey), isEmpty);
    expect(enabled(tester, addButton), isFalse);
    await tester.enterText(find.byKey(secretNameKey), 'OTHER');
    await tester.enterText(find.byKey(secretValueKey), 'value');
    await pumpPage(tester, calls, busy: true);
    expect(enabled(tester, addButton), isFalse);
  });

  testWidgets('a secret-like error is never shown verbatim', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(
      tester,
      calls,
      loaded: false,
      errorMessage: 'Request failed: session=abc123',
    );
    expect(find.text(genericInboxError), findsOneWidget);
    expect(find.textContaining('session=abc123'), findsNothing);
    await pumpPage(tester, calls, errorMessage: 'Network error · timeout');
    expect(find.text('Network error · timeout'), findsOneWidget);
  });

  testWidgets('secret values are never rendered', (WidgetTester tester) async {
    final Calls calls = Calls();
    await pumpPage(
      tester,
      calls,
      secrets: <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'API_KEY',
          'type': 'runtime_secret',
          'value': 'hidden-a',
          'secretValue': 'hidden-b',
        },
        <String, dynamic>{'value': 'hidden-c', 'secretValue': 'hidden-d'},
      ],
    );
    expect(find.text('API_KEY · runtime_secret'), findsOneWidget);
    expect(find.textContaining('hidden-'), findsNothing);
    expect(deleteButtons, findsOneWidget);
  });
}
