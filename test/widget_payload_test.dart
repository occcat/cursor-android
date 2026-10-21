import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:cursor_android/domain/widget_state.dart' as ws;
import 'package:cursor_android/widget/widget_payload.dart';
import 'package:flutter_test/flutter_test.dart';

final int fetched = DateTime(2026, 10, 21, 9, 5).millisecondsSinceEpoch;
final int now = fetched + 60000;
final UsageSnapshot usage = UsageSnapshot(
  cursorUsed: 32,
  otherUsed: 61.4,
  fetchedAt: fetched,
);

List<AgentSummary> agentsOf(int count) => <AgentSummary>[
  for (int index = 0; index < count; index++)
    AgentSummary(bcId: 'bc-$index', name: 'Task $index', status: 'ACTIVE'),
];

const List<String> stableKeys = <String>[
  'usage.metric',
  'usage.status',
  'usage.compactStatus',
  'usage.cursor',
  'usage.other',
  'usage.showCursor',
  'usage.showOther',
  'usage.fetchedAtMs',
  'agents.status',
  'agents.updatedAtMs',
  'agents.count',
  'agents.0.id',
  'agents.0.title',
  'agents.0.status',
  'agents.1.id',
  'agents.1.title',
  'agents.1.status',
  'agents.2.id',
  'agents.2.title',
  'agents.2.status',
  'agents.3.id',
  'agents.3.title',
  'agents.3.status',
  'agents.4.id',
  'agents.4.title',
  'agents.4.status',
  'prefs.language',
  'prefs.remaining',
  'prefs.paused',
  'conn.web',
];

void expectMirrors(WidgetPayload payload, ws.WidgetState state, int nowMs) {
  expect(payload.metricLabel, state.metric());
  expect(payload.usageStatus, state.usageStatus(nowMs));
  expect(payload.compactUsageStatus, state.compactUsageStatus(nowMs));
  expect(payload.cursorValue, state.value(true));
  expect(payload.otherValue, state.value(false));
  expect(payload.showCursor, state.preferences.cursor);
  expect(payload.showOther, state.preferences.other);
  expect(payload.agentStatus, state.agentStatus(nowMs));
  expect(payload.agents, state.agentRows().take(WidgetPayload.maxAgents));
  expect(payload.language, state.preferences.language);
  expect(payload.remaining, state.preferences.remaining);
  expect(payload.paused, state.preferences.paused);
  expect(payload.webConnected, state.webConnected);
  expect(payload.fetchedAtMs, state.usage?.fetchedAt ?? 0);
  expect(payload.agentsUpdatedAtMs, state.agentsUpdatedAtMs);
}

void main() {
  test('fromState mirrors an English connected snapshot', () {
    final ws.WidgetState state = ws.WidgetState(
      usage: usage,
      agents: const <AgentSummary>[
        AgentSummary(bcId: 'bc-1', name: 'Fix login', status: 'ACTIVE'),
      ],
      agentsUpdatedAtMs: fetched,
      preferences: const Preferences(widgetTitles: true),
      webConnected: true,
    );
    final WidgetPayload payload = WidgetPayload.fromState(state, now);
    expectMirrors(payload, state, now);
    expect(payload.metricLabel, 'Remaining');
    expect(payload.usageStatus, 'Updated 10-21 09:05');
    expect(payload.compactUsageStatus, 'Left · 10-21 09:05');
    expect(payload.cursorValue, '68%');
    expect(payload.otherValue, '39%');
    expect(payload.agentStatus, 'Updated 10-21 09:05');
    expect(payload.agents, const <ws.WidgetAgent>[
      ws.WidgetAgent(id: 'bc-1', title: 'Fix login', status: 'Active'),
    ]);
    expect(payload.fetchedAtMs, fetched);
    expect(payload.agentsUpdatedAtMs, fetched);
  });

  test('fromState mirrors a Chinese snapshot with one pool hidden', () {
    final ws.WidgetState state = ws.WidgetState(
      usage: usage,
      agents: agentsOf(1),
      agentsUpdatedAtMs: fetched,
      preferences: const Preferences(
        language: 'zh-CN',
        remaining: false,
        other: false,
      ),
      webConnected: true,
    );
    final WidgetPayload payload = WidgetPayload.fromState(state, now);
    expectMirrors(payload, state, now);
    expect(payload.metricLabel, '已用');
    expect(payload.usageStatus, '更新于 10-21 09:05');
    expect(payload.compactUsageStatus, '已用 · 10-21 09:05');
    expect(payload.cursorValue, '32%');
    expect(payload.otherValue, '61%');
    expect(payload.showCursor, isTrue);
    expect(payload.showOther, isFalse);
    expect(payload.agents, const <ws.WidgetAgent>[
      ws.WidgetAgent(id: 'bc-0', title: '会话 1', status: '活跃'),
    ]);
    expect(payload.language, 'zh-CN');
    expect(payload.remaining, isFalse);
  });

  test('disconnected or missing usage shows dashes and connect status', () {
    final ws.WidgetState offline = ws.WidgetState(
      usage: usage,
      agents: agentsOf(2),
      agentsUpdatedAtMs: fetched,
    );
    final WidgetPayload away = WidgetPayload.fromState(offline, now);
    expectMirrors(away, offline, now);
    expect(away.cursorValue, '—');
    expect(away.otherValue, '—');
    expect(away.usageStatus, 'Connect web session');
    expect(away.compactUsageStatus, 'Connect web session');
    expect(away.agentStatus, 'Sign in');
    expect(away.agents, isEmpty);
    expect(away.webConnected, isFalse);

    const ws.WidgetState empty = ws.WidgetState(webConnected: true);
    final WidgetPayload none = WidgetPayload.fromState(empty, now);
    expectMirrors(none, empty, now);
    expect(none.cursorValue, '—');
    expect(none.usageStatus, 'No snapshot yet');
    expect(none.agentStatus, 'No snapshot yet');
    expect(none.fetchedAtMs, 0);
    expect(none.agentsUpdatedAtMs, isNull);
  });

  test('toHomeWidgetMap writes every stable key', () {
    final WidgetPayload payload = WidgetPayload.fromState(
      ws.WidgetState(
        usage: usage,
        agents: agentsOf(2),
        agentsUpdatedAtMs: fetched,
        webConnected: true,
      ),
      now,
    );
    final Map<String, Object?> map = payload.toHomeWidgetMap();
    expect(map.keys.toSet(), stableKeys.toSet());
    expect(map, hasLength(stableKeys.length));
    expect(map['usage.metric'], 'Remaining');
    expect(map['usage.cursor'], '68%');
    expect(map['usage.showOther'], isTrue);
    expect(map['usage.fetchedAtMs'], fetched);
    expect(map['agents.count'], 2);
    expect(map['agents.1.id'], 'bc-1');
    expect(map['agents.1.title'], 'Agent 2');
    expect(map['agents.1.status'], 'Active');
    expect(map['agents.2.id'], '');
    expect(map['agents.4.status'], '');
    expect(map['prefs.language'], 'en');
    expect(map['conn.web'], isTrue);
  });

  test('a round trip through the map preserves every value', () {
    for (final ws.WidgetState state in <ws.WidgetState>[
      ws.WidgetState(
        usage: usage,
        agents: agentsOf(3),
        agentsUpdatedAtMs: fetched,
        preferences: const Preferences(
          language: 'zh-CN',
          paused: true,
          widgetTitles: true,
        ),
        webConnected: true,
      ),
      ws.WidgetState(usage: usage, webConnected: true),
      const ws.WidgetState(),
    ]) {
      final WidgetPayload payload = WidgetPayload.fromState(state, now);
      final WidgetPayload decoded = WidgetPayload.fromHomeWidgetMap(
        payload.toHomeWidgetMap(),
      );
      expect(decoded, payload);
      expect(decoded.hashCode, payload.hashCode);
    }
  });

  test('agents are capped at five', () {
    final WidgetPayload payload = WidgetPayload.fromState(
      ws.WidgetState(agents: agentsOf(7), webConnected: true),
      now,
    );
    expect(payload.agents, hasLength(5));
    expect(
      payload.agents.map((ws.WidgetAgent agent) => agent.id),
      <String>['bc-0', 'bc-1', 'bc-2', 'bc-3', 'bc-4'],
    );
    final Map<String, Object?> map = payload.toHomeWidgetMap();
    expect(map['agents.count'], 5);
    expect(map.containsKey('agents.5.id'), isFalse);

    final WidgetPayload wide = WidgetPayload(
      metricLabel: payload.metricLabel,
      usageStatus: payload.usageStatus,
      compactUsageStatus: payload.compactUsageStatus,
      cursorValue: payload.cursorValue,
      otherValue: payload.otherValue,
      showCursor: payload.showCursor,
      showOther: payload.showOther,
      agentStatus: payload.agentStatus,
      agents: <ws.WidgetAgent>[
        ...payload.agents,
        const ws.WidgetAgent(id: 'bc-9', title: 'Extra', status: 'Idle'),
      ],
      language: payload.language,
      remaining: payload.remaining,
      paused: payload.paused,
      webConnected: payload.webConnected,
      fetchedAtMs: payload.fetchedAtMs,
      agentsUpdatedAtMs: payload.agentsUpdatedAtMs,
    );
    expect(wide.toHomeWidgetMap()['agents.count'], 5);
    expect(
      WidgetPayload.fromHomeWidgetMap(wide.toHomeWidgetMap()).agents,
      payload.agents,
    );
  });

  test('an empty or mistyped map decodes to the disconnected look', () {
    final WidgetPayload empty = WidgetPayload.fromHomeWidgetMap(
      <String, Object?>{},
    );
    expect(empty, WidgetPayload.fromState(const ws.WidgetState(), 0));
    expect(empty.metricLabel, 'Remaining');
    expect(empty.usageStatus, 'Connect web session');
    expect(empty.compactUsageStatus, 'Connect web session');
    expect(empty.cursorValue, '—');
    expect(empty.otherValue, '—');
    expect(empty.showCursor, isTrue);
    expect(empty.showOther, isTrue);
    expect(empty.agentStatus, 'Sign in');
    expect(empty.agents, isEmpty);
    expect(empty.language, 'en');
    expect(empty.webConnected, isFalse);
    expect(empty.fetchedAtMs, 0);
    expect(empty.agentsUpdatedAtMs, isNull);

    final WidgetPayload mistyped =
        WidgetPayload.fromHomeWidgetMap(<String, Object?>{
          'usage.cursor': 68,
          'usage.showCursor': 'yes',
          'usage.fetchedAtMs': '12',
          'agents.count': 'many',
          'conn.web': 1,
        });
    expect(mistyped, empty);

    final WidgetPayload partial =
        WidgetPayload.fromHomeWidgetMap(<String, Object?>{
          'agents.count': 9,
          'agents.0.id': 'bc-0',
        });
    expect(partial.agents, hasLength(5));
    expect(
      partial.agents.first,
      const ws.WidgetAgent(id: 'bc-0', title: '', status: ''),
    );
    expect(
      WidgetPayload.fromHomeWidgetMap(<String, Object?>{
        'agents.count': -2,
      }).agents,
      isEmpty,
    );
  });
}
