import 'dart:async';

import 'package:cursor_android/ui/create_agent_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const ValueKey<String> promptKey = ValueKey<String>('create-agent-prompt');
const ValueKey<String> reposKey = ValueKey<String>('create-agent-repos');
const String repoUrl = 'https://github.com/occcat/cursor-android';
const List<CreateAgentOption> environments = <CreateAgentOption>[
  (id: 'env-1', label: 'Linux box'),
];
const List<CreateAgentOption> models = <CreateAgentOption>[
  (id: 'gpt-5', label: 'GPT-5'),
];
final Finder start = find.widgetWithText(FilledButton, 'Start agent →');

typedef Submission = ({
  String prompt,
  List<String> repos,
  String model,
  String environment,
});

/// Records every submission; [pending] keeps the call in flight.
class Recorder {
  Recorder([this.pending]);

  final Completer<void>? pending;
  final List<Submission> calls = <Submission>[];

  Future<void> call({
    required String prompt,
    required List<String> repos,
    required String model,
    required String environment,
  }) {
    calls.add((
      prompt: prompt,
      repos: repos,
      model: model,
      environment: environment,
    ));
    return pending?.future ?? Future<void>.value();
  }
}

Future<void> pumpPage(
  WidgetTester tester, {
  Recorder? recorder,
  bool busy = false,
  List<String> recentRepos = const <String>[
    repoUrl,
    'https://github.com/a/b',
  ],
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CreateAgentPage(
          busy: busy,
          recentRepos: recentRepos,
          environments: environments,
          models: models,
          onSubmit: recorder?.call,
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

Future<void> typeInto(
  WidgetTester tester,
  ValueKey<String> key,
  String text,
) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

bool startEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(start).onPressed != null;

TextField reposField(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(reposKey));

bool chipSelected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;

void main() {
  testWidgets('Start agent needs a non-blank prompt and onSubmit', (
    WidgetTester tester,
  ) async {
    await pumpPage(tester, recorder: Recorder());
    expect(startEnabled(tester), isFalse);
    await typeInto(tester, promptKey, '  \n  ');
    expect(startEnabled(tester), isFalse);
    await typeInto(tester, promptKey, 'Fix the login bug');
    expect(startEnabled(tester), isTrue);
    await pumpPage(tester);
    expect(startEnabled(tester), isFalse);
  });

  testWidgets('Start agent is disabled while busy', (
    WidgetTester tester,
  ) async {
    final Recorder recorder = Recorder();
    await pumpPage(tester, recorder: recorder, busy: true);
    await typeInto(tester, promptKey, 'Fix the login bug');
    expect(startEnabled(tester), isFalse);
    await tapVisible(tester, start);
    expect(recorder.calls, isEmpty);
  });

  testWidgets('Start agent submits the trimmed prompt, repos and model', (
    WidgetTester tester,
  ) async {
    final Recorder recorder = Recorder();
    await pumpPage(tester, recorder: recorder);
    await typeInto(tester, promptKey, '  Fix the login bug  ');
    await typeInto(
      tester,
      reposKey,
      'https://github.com/a/b\n\n  https://github.com/c/d  \n',
    );
    await tapVisible(tester, find.text('GPT-5'));
    await tapVisible(tester, start);
    final Submission call = recorder.calls.single;
    expect(call.prompt, 'Fix the login bug');
    expect(call.repos, <String>[
      'https://github.com/a/b',
      'https://github.com/c/d',
    ]);
    expect(call.model, 'gpt-5');
    expect(call.environment, '');
  });

  testWidgets('an environment clears and disables the repository field', (
    WidgetTester tester,
  ) async {
    final Recorder recorder = Recorder();
    await pumpPage(tester, recorder: recorder);
    await typeInto(tester, reposKey, 'https://github.com/a/b');
    await tapVisible(tester, find.text('Linux box'));
    expect(reposField(tester).controller!.text, isEmpty);
    expect(reposField(tester).enabled, isFalse);
    expect(chipSelected(tester, 'Linux box'), isTrue);
    expect(chipSelected(tester, 'Default environment'), isFalse);
    await typeInto(tester, promptKey, 'Task');
    await tapVisible(tester, start);
    expect(recorder.calls.single.environment, 'env-1');
    expect(recorder.calls.single.repos, isEmpty);
  });

  testWidgets('a recent repository fills the field and clears the environment', (
    WidgetTester tester,
  ) async {
    final Recorder recorder = Recorder();
    await pumpPage(tester, recorder: recorder);
    await tapVisible(tester, find.text('Linux box'));
    await tapVisible(tester, find.text('cursor-android'));
    expect(reposField(tester).controller!.text, repoUrl);
    expect(reposField(tester).enabled, isTrue);
    expect(chipSelected(tester, 'Default environment'), isTrue);
    await typeInto(tester, promptKey, 'Task');
    await tapVisible(tester, start);
    expect(recorder.calls.single.repos, <String>[repoUrl]);
    expect(recorder.calls.single.environment, '');
  });

  testWidgets('Account default sends an empty model', (
    WidgetTester tester,
  ) async {
    final Recorder recorder = Recorder();
    await pumpPage(tester, recorder: recorder);
    await tapVisible(tester, find.text('GPT-5'));
    expect(chipSelected(tester, 'GPT-5'), isTrue);
    await tapVisible(tester, find.text('Account default'));
    expect(chipSelected(tester, 'Account default'), isTrue);
    await typeInto(tester, promptKey, 'Task');
    await tapVisible(tester, start);
    expect(recorder.calls.single.model, '');
  });

  testWidgets('at most 10 non-blank recent repositories are shown', (
    WidgetTester tester,
  ) async {
    await pumpPage(
      tester,
      recorder: Recorder(),
      recentRepos: <String>[
        '  ',
        for (int index = 0; index < 12; index++) 'https://github.com/o/r$index',
      ],
    );
    expect(find.byType(ActionChip), findsNWidgets(10));
    expect(find.text('r9'), findsOneWidget);
    expect(find.text('r10'), findsNothing);
  });

  testWidgets('Start agent stays disabled while a submission is in flight', (
    WidgetTester tester,
  ) async {
    final Completer<void> pending = Completer<void>();
    final Recorder recorder = Recorder(pending);
    await pumpPage(tester, recorder: recorder);
    await typeInto(tester, promptKey, 'Task');
    await tapVisible(tester, start);
    expect(startEnabled(tester), isFalse);
    await tapVisible(tester, start);
    expect(recorder.calls, hasLength(1));
    pending.complete();
    await tester.pumpAndSettle();
    expect(startEnabled(tester), isTrue);
  });

  test('options map catalog rows and skip rows without an id', () {
    expect(
      environmentOptions(<Map<String, dynamic>>[
        <String, dynamic>{'publicId': 'env-1', 'name': 'Linux box'},
        <String, dynamic>{'publicId': 'env-2', 'name': '  '},
        <String, dynamic>{'name': 'No id'},
        <String, dynamic>{'publicId': 3, 'name': 'Number id'},
      ]),
      <CreateAgentOption>[
        (id: 'env-1', label: 'Linux box'),
        (id: 'env-2', label: 'env-2'),
      ],
    );
    expect(
      modelOptions(<Map<String, dynamic>>[
        <String, dynamic>{
          'serverModelName': 'gpt-5',
          'clientDisplayName': 'GPT-5',
        },
        <String, dynamic>{'serverModelName': 'claude'},
        <String, dynamic>{'serverModelName': ''},
      ]),
      <CreateAgentOption>[
        (id: 'gpt-5', label: 'GPT-5'),
        (id: 'claude', label: 'claude'),
      ],
    );
  });
}
