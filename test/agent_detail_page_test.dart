import 'package:cursor_android/ui/agent_detail_page.dart';
import 'package:cursor_android/ui/agent_status.dart';
import 'package:cursor_android/ui/inbox_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String agentId = 'bc-1';
const ValueKey<String> followUpKey = ValueKey<String>('agent-follow-up');
final Finder sendButton = find.widgetWithText(FilledButton, 'Send follow-up');

Map<String, dynamic> agentWith({
  String name = 'Fix login',
  String status = 'RUNNING',
}) => <String, dynamic>{'bcId': agentId, 'name': name, 'status': status};

/// Records every callback the page invokes.
class Calls {
  int refresh = 0;
  int pause = 0;
  int archive = 0;
  int unarchive = 0;
  final List<String> followUps = <String>[];
  final List<Map<String, dynamic>> opened = <Map<String, dynamic>>[];
  String? artifactBody = 'hello';

  void onRefresh() {
    refresh++;
  }

  Future<void> onPause() async {
    pause++;
  }

  Future<void> onArchive() async {
    archive++;
  }

  Future<void> onUnarchive() async {
    unarchive++;
  }

  Future<void> onFollowUp(String prompt) async {
    followUps.add(prompt);
  }

  Future<String?> onOpenArtifact(Map<String, dynamic> artifact) async {
    opened.add(artifact);
    return artifactBody;
  }
}

Future<void> pumpPage(
  WidgetTester tester,
  Calls calls, {
  Map<String, dynamic>? agent,
  bool busy = false,
  bool pauseUnavailable = false,
  bool showArtifacts = false,
  List<Map<String, dynamic>> artifacts = const <Map<String, dynamic>>[],
  String streamText = '',
  String? errorMessage,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AgentDetailPage(
          bcId: agentId,
          agent: agent,
          busy: busy,
          pauseUnavailable: pauseUnavailable,
          showArtifacts: showArtifacts,
          artifacts: artifacts,
          streamText: streamText,
          errorMessage: errorMessage,
          onRefresh: calls.onRefresh,
          onOpenArtifact: calls.onOpenArtifact,
          onFollowUp: calls.onFollowUp,
          onPause: calls.onPause,
          onArchive: calls.onArchive,
          onUnarchive: calls.onUnarchive,
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

Finder chip(String label) => find.widgetWithText(ActionChip, label);

bool sendEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(sendButton).onPressed != null;

void main() {
  testWidgets('a missing or mismatched agent shows Retry', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls);
    expect(find.text('Loading this workspace…'), findsOneWidget);
    await tapVisible(tester, chip('Retry'));
    expect(calls.refresh, 1);
    await pumpPage(
      tester,
      calls,
      agent: <String, dynamic>{
        'bcId': 'bc-other',
        'name': 'Other',
        'status': 'RUNNING',
      },
    );
    expect(find.text('Loading this workspace…'), findsOneWidget);
    expect(find.text('Other'), findsNothing);
  });

  testWidgets('the name and status render and a blank name reads Agent', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith());
    expect(find.text('Fix login'), findsOneWidget);
    expect(find.byType(AgentStatus), findsOneWidget);
    expect(find.text('RUNNING'), findsOneWidget);
    await pumpPage(tester, calls, agent: agentWith(name: '  '));
    expect(find.text('Agent'), findsOneWidget);
  });

  testWidgets('Pause is hidden when finished and shown while running', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith(status: 'FINISHED'));
    expect(chip('Pause'), findsNothing);
    await pumpPage(tester, calls, agent: agentWith());
    expect(chip('Pause'), findsOneWidget);
    expect(find.text('This response cannot pause the agent.'), findsNothing);
  });

  testWidgets('Pause unavailable is labelled, explained and disabled', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith(), pauseUnavailable: true);
    expect(chip('Pause'), findsNothing);
    expect(
      tester.widget<ActionChip>(chip('Pause unavailable')).onPressed,
      isNull,
    );
    expect(find.text('This response cannot pause the agent.'), findsOneWidget);
  });

  testWidgets('Archive turns into Restore for an archived agent', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith());
    expect(chip('Archive'), findsOneWidget);
    expect(chip('Restore'), findsNothing);
    await pumpPage(tester, calls, agent: agentWith(status: 'ARCHIVED'));
    expect(chip('Restore'), findsOneWidget);
    expect(chip('Archive'), findsNothing);
    expect(chip('Pause'), findsNothing);
  });

  testWidgets('Keep dismisses the pause dialog and Confirm pauses', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith());
    await tapVisible(tester, chip('Pause'));
    expect(find.text('Confirm agent action'), findsOneWidget);
    expect(find.text('Pause this agent?'), findsOneWidget);
    await tapVisible(tester, find.text('Keep'));
    expect(find.text('Pause this agent?'), findsNothing);
    expect(calls.pause, 0);
    await tapVisible(tester, chip('Pause'));
    await tapVisible(tester, find.text('Confirm'));
    expect(calls.pause, 1);
    expect(find.text('Pause this agent?'), findsNothing);
  });

  testWidgets('Confirm archives or restores the agent', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith());
    await tapVisible(tester, chip('Archive'));
    expect(find.text('Archive this agent?'), findsOneWidget);
    await tapVisible(tester, find.text('Confirm'));
    expect(calls.archive, 1);
    await pumpPage(tester, calls, agent: agentWith(status: 'ARCHIVED'));
    await tapVisible(tester, chip('Restore'));
    expect(find.text('Restore this agent?'), findsOneWidget);
    await tapVisible(tester, find.text('Confirm'));
    expect(calls.unarchive, 1);
    expect(calls.archive, 1);
  });

  testWidgets('Send follow-up is disabled when blank or busy', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith());
    expect(sendEnabled(tester), isFalse);
    await tester.enterText(find.byKey(followUpKey), '  \n ');
    await tester.pump();
    expect(sendEnabled(tester), isFalse);
    await pumpPage(tester, calls, agent: agentWith(), busy: true);
    await tester.enterText(find.byKey(followUpKey), 'Next step');
    await tester.pump();
    expect(sendEnabled(tester), isFalse);
  });

  testWidgets('Send follow-up sends the trimmed text and clears the field', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith());
    await tester.enterText(find.byKey(followUpKey), '  Next step  ');
    await tester.pump();
    expect(sendEnabled(tester), isTrue);
    await tapVisible(tester, sendButton);
    expect(calls.followUps, <String>['Next step']);
    expect(
      tester.widget<TextField>(find.byKey(followUpKey)).controller!.text,
      isEmpty,
    );
    expect(sendEnabled(tester), isFalse);
  });

  testWidgets('artifacts without a title show the empty copy', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith(), showArtifacts: true);
    expect(find.text('No artifacts returned.'), findsOneWidget);
    await pumpPage(
      tester,
      calls,
      agent: agentWith(),
      showArtifacts: true,
      artifacts: <Map<String, dynamic>>[
        <String, dynamic>{'size': 1, 'path': '  '},
      ],
    );
    expect(find.text('No artifacts returned.'), findsOneWidget);
    await pumpPage(
      tester,
      calls,
      agent: agentWith(),
      artifacts: <Map<String, dynamic>>[
        <String, dynamic>{'path': 'a.txt'},
      ],
    );
    expect(find.text('a.txt'), findsNothing);
    expect(find.text('No artifacts returned.'), findsNothing);
  });

  testWidgets('tapping an artifact title opens its content', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    final Map<String, dynamic> file = <String, dynamic>{
      'path': 'out/a.txt',
      'name': 'a',
    };
    await pumpPage(
      tester,
      calls,
      agent: agentWith(),
      showArtifacts: true,
      artifacts: <Map<String, dynamic>>[
        <String, dynamic>{'name': 'b.png'},
        file,
      ],
    );
    expect(find.text('b.png'), findsOneWidget);
    await tapVisible(tester, find.text('out/a.txt'));
    expect(calls.opened.single, same(file));
    expect(find.text('Artifact'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    await tapVisible(tester, find.text('Close'));
    expect(find.text('hello'), findsNothing);
    calls.artifactBody = '  ';
    await tapVisible(tester, find.text('b.png'));
    expect(find.text('No bytes returned.'), findsOneWidget);
  });

  testWidgets('the conversation card appears only with text', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(tester, calls, agent: agentWith(), streamText: '  ');
    expect(find.text('Conversation'), findsNothing);
    await pumpPage(tester, calls, agent: agentWith(), streamText: 'Hello');
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('a secret-like error is never shown verbatim', (
    WidgetTester tester,
  ) async {
    final Calls calls = Calls();
    await pumpPage(
      tester,
      calls,
      agent: agentWith(),
      errorMessage: 'Request failed: session=abc123',
    );
    expect(find.text(genericInboxError), findsOneWidget);
    expect(find.textContaining('session=abc123'), findsNothing);
    await pumpPage(
      tester,
      calls,
      agent: agentWith(),
      errorMessage: 'Network error · timeout',
    );
    expect(find.text('Network error · timeout'), findsOneWidget);
  });
}
