import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/main.dart' show buildTheme;
import 'package:cursor_android/ui/agent_list_tile.dart';
import 'package:cursor_android/ui/agent_status.dart';
import 'package:cursor_android/ui/cursor_colors.dart';
import 'package:cursor_android/ui/usage_panel.dart' show formatUsageTime;
import 'package:cursor_android/ui/usage_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] in the app theme and lets any theme transition finish.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Color dotColor(WidgetTester tester) =>
    tester.widget<UsageDot>(find.byType(UsageDot)).color;

const List<AgentSummary> agents = <AgentSummary>[
  AgentSummary(bcId: 'bc-1', name: 'Fix Login', status: 'RUNNING'),
  AgentSummary(bcId: 'bc-2', name: 'Old login page', status: 'ARCHIVED'),
  AgentSummary(bcId: 'bc-3', name: 'Docs', status: 'FINISHED'),
];

List<String> ids(List<AgentSummary> list) =>
    <String>[for (final AgentSummary agent in list) agent.bcId];

void main() {
  group('AgentSummary.fromJson', () {
    test('reads the Kotlin fields', () {
      final AgentSummary agent = AgentSummary.fromJson(<String, dynamic>{
        'bcId': 'bc-1',
        'name': 'Fix login',
        'status': 'RUNNING',
        'updatedAtMs': '1700000000000',
        'updatedAt': '2 days ago',
      });
      expect(agent.bcId, 'bc-1');
      expect(agent.name, 'Fix login');
      expect(agent.status, 'RUNNING');
      expect(agent.updatedAtMs, 1700000000000);
      expect(agent.updatedAtLabel, '2 days ago');
    });

    test('missing and non-scalar fields become empty', () {
      final AgentSummary agent = AgentSummary.fromJson(<String, dynamic>{
        'name': null,
        'status': <String, dynamic>{},
        'bcId': 42,
      });
      expect(agent.bcId, '42');
      expect(agent.name, '');
      expect(agent.status, '');
      expect(agent.updatedAtMs, isNull);
      expect(agent.updatedAtLabel, '');
    });

    test('updatedAtMs accepts only whole numbers', () {
      int? millis(Object? value) =>
          AgentSummary.fromJson(<String, dynamic>{
            'updatedAtMs': value,
          }).updatedAtMs;
      expect(millis(1700000000000), 1700000000000);
      expect(millis('+5'), 5);
      expect(millis('1.5'), isNull);
      expect(millis(1.7e12), isNull);
      expect(millis('0x10'), isNull);
      expect(millis(' 5'), isNull);
      expect(millis(true), isNull);
    });
  });

  test('agentsFromComposers keeps only object entries', () {
    expect(agentsFromComposers(null), isEmpty);
    expect(agentsFromComposers(<String, dynamic>{}), isEmpty);
    expect(agentsFromComposers(<String, dynamic>{'composers': 'x'}), isEmpty);
    final List<AgentSummary> parsed = agentsFromComposers(<String, dynamic>{
      'composers': <Object?>[
        <String, dynamic>{'bcId': 'a', 'name': 'One'},
        3,
        null,
        'text',
        <String, dynamic>{'bcId': 'b', 'name': 'Two'},
      ],
    });
    expect(ids(parsed), <String>['a', 'b']);
    expect(parsed.last.name, 'Two');
  });

  group('filterAgents', () {
    test('hides ARCHIVED unless includeArchived', () {
      expect(
        ids(filterAgents(agents, query: '', includeArchived: false)),
        <String>['bc-1', 'bc-3'],
      );
      expect(
        ids(filterAgents(agents, query: '', includeArchived: true)),
        <String>['bc-1', 'bc-2', 'bc-3'],
      );
    });

    test('matches the name ignoring case', () {
      expect(
        ids(filterAgents(agents, query: 'login', includeArchived: false)),
        <String>['bc-1'],
      );
      expect(
        ids(filterAgents(agents, query: 'LOGIN', includeArchived: true)),
        <String>['bc-1', 'bc-2'],
      );
      expect(
        filterAgents(agents, query: 'nothing', includeArchived: true),
        isEmpty,
      );
    });
  });

  test('agentStatusColor maps statuses like Kotlin', () {
    const Brightness light = Brightness.light;
    expect(agentStatusColor('RUNNING', light), cursorAccent);
    expect(agentStatusColor('CREATING', light), cursorAccent);
    expect(agentStatusColor('FINISHED', light), successLight);
    expect(agentStatusColor('ERROR', light), errorLight);
    expect(agentStatusColor('FAILED', light), errorLight);
    expect(agentStatusColor('EXPIRED', light), errorLight);
    expect(agentStatusColor('ARCHIVED', light), textTertiaryLight);
    expect(agentStatusColor('PAUSED', light), poolOtherLight);
    expect(agentStatusColor('running', light), poolOtherLight);
    expect(agentStatusColor('FINISHED', Brightness.dark), successDark);
    expect(agentStatusColor('ERROR', Brightness.dark), errorDark);
    expect(agentStatusColor('ARCHIVED', Brightness.dark), textTertiaryDark);
    expect(agentStatusColor('', Brightness.dark), poolOtherDark);
  });

  test('status colors match Kotlin CursorTheme', () {
    expect(successColor(Brightness.light), const Color(0xFF17775A));
    expect(successColor(Brightness.dark), const Color(0xFF3FB68B));
    expect(errorColor(Brightness.light), const Color(0xFFB8244A));
    expect(errorColor(Brightness.dark), const Color(0xFFE5506F));
    expect(textSecondaryColor(Brightness.light), const Color(0xFF676660));
    expect(textSecondaryColor(Brightness.dark), const Color(0xFF969592));
    expect(textTertiaryColor(Brightness.light), const Color(0xFFA3A39E));
    expect(textTertiaryColor(Brightness.dark), const Color(0xFF6B6965));
    expect(poolCursor, cursorAccent);
  });

  testWidgets('AgentStatus shows the status verbatim with a tinted dot', (
    WidgetTester tester,
  ) async {
    await pumpThemed(tester, const AgentStatus(status: 'RUNNING'));
    expect(find.text('RUNNING'), findsOneWidget);
    expect(dotColor(tester), cursorAccent);
    expect(tester.getSize(find.byType(UsageDot)), const Size(6, 6));

    await pumpThemed(tester, const AgentStatus(status: 'FINISHED'));
    expect(dotColor(tester), successLight);

    await pumpThemed(
      tester,
      const AgentStatus(status: 'FINISHED'),
      brightness: Brightness.dark,
    );
    expect(dotColor(tester), successDark);

    await pumpThemed(tester, const AgentStatus(status: 'Waiting for input'));
    expect(find.text('Waiting for input'), findsOneWidget);
    expect(dotColor(tester), poolOtherLight);
  });

  testWidgets('AgentListTile shows the name, status and updated label', (
    WidgetTester tester,
  ) async {
    const int millis = 1700000000000;
    await pumpThemed(
      tester,
      const AgentListTile(
        agent: AgentSummary(
          bcId: 'bc-1',
          name: 'Fix login',
          status: 'ERROR',
          updatedAtMs: millis,
          updatedAtLabel: 'ignored',
        ),
      ),
    );
    expect(find.text('Fix login'), findsOneWidget);
    expect(find.text('ERROR'), findsOneWidget);
    expect(dotColor(tester), errorLight);
    expect(find.text(formatUsageTime(millis)), findsOneWidget);
    expect(find.text('ignored'), findsNothing);

    await pumpThemed(
      tester,
      const AgentListTile(
        agent: AgentSummary(name: 'Docs', updatedAtLabel: 'yesterday'),
      ),
    );
    expect(find.text('yesterday'), findsOneWidget);
  });

  testWidgets('a blank name shows Untitled agent and taps call onTap', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await pumpThemed(
      tester,
      AgentListTile(
        agent: const AgentSummary(name: '   ', status: 'RUNNING'),
        onTap: () => taps++,
      ),
    );
    expect(find.text('Untitled agent'), findsOneWidget);
    await tester.tap(find.byType(AgentListTile));
    expect(taps, 1);
  });

  test('agentUpdatedLabel prefers milliseconds over the API text', () {
    expect(
      agentUpdatedLabel(
        const AgentSummary(updatedAtMs: 0, updatedAtLabel: 'later'),
      ),
      formatUsageTime(0),
    );
    expect(
      agentUpdatedLabel(const AgentSummary(updatedAtLabel: 'later')),
      'later',
    );
    expect(agentUpdatedLabel(const AgentSummary()), '');
  });
}
