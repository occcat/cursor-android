import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:cursor_android/main.dart' show buildTheme;
import 'package:cursor_android/ui/agent_list_tile.dart';
import 'package:cursor_android/ui/inbox_page.dart';
import 'package:cursor_android/ui/usage_capsule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final List<AgentSummary> sampleAgents = agentsFromComposers(<String, dynamic>{
  'composers': <Object?>[
    <String, dynamic>{'bcId': 'bc-1', 'name': 'Fix login', 'status': 'RUNNING'},
    <String, dynamic>{
      'bcId': 'bc-2',
      'name': 'Old login page',
      'status': 'ARCHIVED',
    },
    <String, dynamic>{'bcId': 'bc-3', 'name': 'Docs', 'status': 'FINISHED'},
  ],
});

Future<void> pumpInbox(
  WidgetTester tester, {
  bool webConnected = true,
  bool loading = false,
  bool busy = false,
  String? errorMessage,
  List<AgentSummary> agents = const <AgentSummary>[],
  bool hasMore = false,
  UsageSnapshot? usage,
  Preferences preferences = const Preferences(),
  VoidCallback? onSignIn,
  VoidCallback? onCreate,
  VoidCallback? onRefresh,
  VoidCallback? onLoadMore,
  ValueChanged<String>? onOpenAgent,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: InboxPage(
          webConnected: webConnected,
          loading: loading,
          busy: busy,
          errorMessage: errorMessage,
          agents: agents,
          hasMore: hasMore,
          usage: usage,
          preferences: preferences,
          onSignIn: onSignIn,
          onCreate: onCreate,
          onRefresh: onRefresh,
          onLoadMore: onLoadMore,
          onOpenAgent: onOpenAgent,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
  await tester.tap(find.text(text));
  await tester.pump();
}

FilledButton button(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

void main() {
  testWidgets('disconnected shows the connect card and Get started', (
    WidgetTester tester,
  ) async {
    int signIns = 0;
    await pumpInbox(tester, webConnected: false, onSignIn: () => signIns++);
    expect(find.text('Your work.\nWithin reach.'), findsOneWidget);
    expect(find.text('Connect your workspace'), findsOneWidget);
    expect(find.text('Continue on Cursor Web'), findsOneWidget);
    expect(find.text('Search agents'), findsNothing);
    expect(find.text('+ New agent'), findsNothing);
    expect(find.text('Open Cursor Web ↗'), findsNothing);
    await tapText(tester, 'Get started');
    expect(signIns, 1);
    expect(
      find.text('Independent community client. Not affiliated with Cursor.'),
      findsOneWidget,
    );
  });

  testWidgets('connected with no agents shows the empty copy', (
    WidgetTester tester,
  ) async {
    await pumpInbox(tester);
    expect(find.text('No agents here yet. Start with a task.'), findsOneWidget);
    expect(find.text('Connect your workspace'), findsNothing);
    expect(find.text('Load more'), findsNothing);
    expect(find.byType(AgentListTile), findsNothing);
  });

  testWidgets('search and Include archived filter the agent tiles', (
    WidgetTester tester,
  ) async {
    await pumpInbox(tester, agents: sampleAgents);
    expect(find.text('Fix login'), findsOneWidget);
    expect(find.text('Docs'), findsOneWidget);
    expect(find.text('Old login page'), findsNothing);
    expect(find.byType(AgentListTile), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'LOGIN');
    await tester.pump();
    expect(find.text('Fix login'), findsOneWidget);
    expect(find.text('Docs'), findsNothing);

    await tapText(tester, 'Include archived');
    expect(find.text('Old login page'), findsOneWidget);
    expect(find.byType(AgentListTile), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.pump();
    expect(find.byType(AgentListTile), findsNothing);
    expect(find.text('No agents here yet. Start with a task.'), findsOneWidget);
  });

  testWidgets('loading with no agents shows a progress indicator', (
    WidgetTester tester,
  ) async {
    await pumpInbox(tester, loading: true, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No agents here yet. Start with a task.'), findsNothing);
  });

  testWidgets('loading with agents keeps the list and shows a thin bar', (
    WidgetTester tester,
  ) async {
    await pumpInbox(
      tester,
      loading: true,
      agents: sampleAgents,
      settle: false,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Fix login'), findsOneWidget);
  });

  testWidgets('a safe error message is shown in the error color', (
    WidgetTester tester,
  ) async {
    const String message = 'Could not refresh agents · HTTP 500';
    await pumpInbox(tester, errorMessage: message, agents: sampleAgents);
    final Text text = tester.widget<Text>(find.text(message));
    final BuildContext context = tester.element(find.byType(InboxPage));
    expect(text.style?.color, Theme.of(context).colorScheme.error);
    expect(find.text('Fix login'), findsOneWidget);
  });

  testWidgets('an error that looks like a secret is never displayed', (
    WidgetTester tester,
  ) async {
    await pumpInbox(
      tester,
      errorMessage: 'Request failed: Cookie: session=secret',
    );
    expect(find.text(genericInboxError), findsOneWidget);
    expect(find.textContaining('session=secret'), findsNothing);
    expect(find.textContaining('Cookie'), findsNothing);
  });

  test('safeInboxError keeps safe text and hides secret-looking text', () {
    const String safe = 'Network error · timeout';
    expect(safeInboxError(safe), safe);
    for (final String unsafe in <String>[
      'session=abc',
      'Set-Cookie: x',
      'Bearer abc',
      'Authorization header',
      'csrf-token=old',
      'client secret leaked',
    ]) {
      expect(safeInboxError(unsafe), genericInboxError, reason: unsafe);
    }
  });

  testWidgets('Load more and agent taps call back with the bcId', (
    WidgetTester tester,
  ) async {
    int loads = 0;
    final List<String> opened = <String>[];
    await pumpInbox(
      tester,
      agents: sampleAgents,
      hasMore: true,
      onLoadMore: () => loads++,
      onOpenAgent: opened.add,
    );
    await tapText(tester, 'Load more');
    expect(loads, 1);
    await tapText(tester, 'Docs');
    await tapText(tester, 'Fix login');
    expect(opened, <String>['bc-3', 'bc-1']);
  });

  testWidgets('+ New agent is disabled while busy', (
    WidgetTester tester,
  ) async {
    int creates = 0;
    await pumpInbox(tester, onCreate: () => creates++, onRefresh: () {});
    expect(button(tester, '+ New agent').enabled, isTrue);
    await tapText(tester, '+ New agent');
    expect(creates, 1);

    await pumpInbox(
      tester,
      busy: true,
      onCreate: () => creates++,
      onRefresh: () {},
    );
    expect(button(tester, '+ New agent').enabled, isFalse);
    expect(button(tester, 'Refresh').enabled, isTrue);
    await tapText(tester, '+ New agent');
    expect(creates, 1);
  });

  testWidgets('the usage capsule follows the pool preferences', (
    WidgetTester tester,
  ) async {
    await pumpInbox(
      tester,
      usage: const UsageSnapshot(cursorUsed: 32, otherUsed: 61),
    );
    expect(find.byType(UsageCapsule), findsOneWidget);
    expect(find.text('● Cursor 68%'), findsOneWidget);

    await pumpInbox(
      tester,
      preferences: const Preferences(cursor: false, other: false),
    );
    expect(find.byType(UsageCapsule), findsNothing);
  });
}
