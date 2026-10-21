import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:cursor_android/domain/widget_state.dart' as ws;
import 'package:flutter_test/flutter_test.dart';

final int fetched = DateTime(2026, 10, 21, 9, 5).millisecondsSinceEpoch;
final int fresh = fetched + 60000;
final int stale = fetched + ws.WidgetState.staleAfterMs + 1;
const Preferences chinese = Preferences(language: 'zh-CN');

ws.WidgetState state({
  UsageSnapshot? usage,
  List<AgentSummary> agents = const <AgentSummary>[],
  int? agentsUpdatedAtMs,
  Preferences preferences = const Preferences(),
  bool webConnected = true,
}) => ws.WidgetState(
  usage: usage,
  agents: agents,
  agentsUpdatedAtMs: agentsUpdatedAtMs,
  preferences: preferences,
  webConnected: webConnected,
);

UsageSnapshot snapshot({
  double? cursorUsed = 32,
  double? otherUsed = 61.4,
  bool unlimited = false,
  int? cycleEnd,
}) => UsageSnapshot(
  cursorUsed: cursorUsed,
  otherUsed: otherUsed,
  unlimited: unlimited,
  cycleEnd: cycleEnd,
  fetchedAt: fetched,
);

const List<AgentSummary> agents = <AgentSummary>[
  AgentSummary(bcId: 'bc-1', name: 'Fix login', status: 'ACTIVE'),
  AgentSummary(bcId: 'bc-2', name: '  ', status: 'IDLE'),
  AgentSummary(bcId: 'bc-3', status: 'ARCHIVED'),
  AgentSummary(bcId: 'bc-4', name: 'Docs', status: 'RUNNING'),
];

void main() {
  test('text and metric follow language and remaining', () {
    expect(state().text('Hello', '你好'), 'Hello');
    expect(state(preferences: chinese).text('Hello', '你好'), '你好');
    expect(state().metric(), 'Remaining');
    expect(state(preferences: chinese).metric(), '剩余');
    const Preferences used = Preferences(remaining: false);
    expect(state(preferences: used).metric(), 'Used');
    expect(
      state(preferences: chinese.copyWith(remaining: false)).metric(),
      '已用',
    );
  });

  test('value shows a dash, infinity or a rounded percent', () {
    expect(state(usage: snapshot(), webConnected: false).value(true), '—');
    expect(state().value(true), '—');
    expect(state(usage: snapshot(unlimited: true)).value(false), '∞');
    expect(state(usage: snapshot()).value(true), '68%');
    expect(state(usage: snapshot()).value(false), '39%');
    const Preferences used = Preferences(remaining: false);
    expect(state(usage: snapshot(), preferences: used).value(true), '32%');
    expect(state(usage: snapshot(), preferences: used).value(false), '61%');
    expect(
      state(usage: snapshot(cursorUsed: 12.5), preferences: used).value(true),
      '13%',
    );
    expect(state(usage: snapshot(cursorUsed: null)).value(true), '—');
  });

  test('usageStatus covers every branch in order', () {
    const Preferences hidden = Preferences(cursor: false, other: false);
    expect(
      state(usage: snapshot(), preferences: hidden).usageStatus(fresh),
      'Pools hidden',
    );
    expect(
      state(
        preferences: hidden.copyWith(language: 'zh-CN'),
        webConnected: false,
      ).usageStatus(fresh),
      '模型用量已隐藏',
    );
    expect(
      state(usage: snapshot(), webConnected: false).usageStatus(fresh),
      'Connect web session',
    );
    expect(state().usageStatus(fresh), 'No snapshot yet');
    expect(
      state(usage: snapshot(cycleEnd: fresh - 1)).usageStatus(stale),
      'Awaiting reset · cached',
    );
    expect(
      state(usage: snapshot()).usageStatus(stale),
      'Stale · 10-21 09:05',
    );
    expect(
      state(
        usage: snapshot(),
        preferences: const Preferences(paused: true),
      ).usageStatus(fresh),
      'Paused · 10-21 09:05',
    );
    expect(
      state(usage: snapshot()).usageStatus(fresh),
      'Updated 10-21 09:05',
    );
    expect(
      state(
        usage: snapshot(),
        preferences: const Preferences(cursor: false),
      ).usageStatus(fresh),
      'Updated 10-21 09:05',
    );
    expect(
      state(usage: snapshot(), preferences: chinese).usageStatus(fresh),
      '更新于 10-21 09:05',
    );
    expect(
      state(usage: snapshot(), preferences: chinese).usageStatus(stale),
      '已过期 · 10-21 09:05',
    );
  });

  test('compactUsageStatus joins metric, qualifier and time', () {
    const Preferences hidden = Preferences(cursor: false, other: false);
    expect(
      state(usage: snapshot(), preferences: hidden).compactUsageStatus(fresh),
      'Pools hidden',
    );
    expect(
      state(usage: snapshot(), webConnected: false).compactUsageStatus(fresh),
      'Connect web session',
    );
    expect(state().compactUsageStatus(fresh), 'No snapshot yet');
    expect(
      state(usage: snapshot()).compactUsageStatus(fresh),
      'Left · 10-21 09:05',
    );
    expect(
      state(
        usage: snapshot(),
        preferences: const Preferences(remaining: false),
      ).compactUsageStatus(fresh),
      'Used · 10-21 09:05',
    );
    expect(
      state(usage: snapshot(cycleEnd: fresh - 1)).compactUsageStatus(fresh),
      'Left · reset due · 09:05',
    );
    expect(
      state(usage: snapshot()).compactUsageStatus(stale),
      'Left · stale · 09:05',
    );
    expect(
      state(
        usage: snapshot(),
        preferences: const Preferences(paused: true),
      ).compactUsageStatus(fresh),
      'Left · paused · 09:05',
    );
    expect(
      state(
        usage: snapshot(cycleEnd: fresh - 1),
        preferences: chinese,
      ).compactUsageStatus(fresh),
      '剩余 · 待重置 · 09:05',
    );
  });

  test('agentStatus covers sign in, missing, stale and fresh', () {
    expect(state(webConnected: false).agentStatus(fresh), 'Sign in');
    expect(
      state(webConnected: false, preferences: chinese).agentStatus(fresh),
      '登录',
    );
    expect(state().agentStatus(fresh), 'No snapshot yet');
    expect(
      state(agentsUpdatedAtMs: fetched).agentStatus(stale),
      'Stale · 10-21 09:05',
    );
    expect(
      state(agentsUpdatedAtMs: fetched).agentStatus(fresh),
      'Updated 10-21 09:05',
    );
    expect(
      state(agentsUpdatedAtMs: fetched, preferences: chinese).agentStatus(fresh),
      '更新于 10-21 09:05',
    );
  });

  test('agentRows number titles unless widget titles are on', () {
    expect(state(agents: agents).agentRows(), const <ws.WidgetAgent>[
      ws.WidgetAgent(id: 'bc-1', title: 'Agent 1', status: 'Active'),
      ws.WidgetAgent(id: 'bc-2', title: 'Agent 2', status: 'Idle'),
      ws.WidgetAgent(id: 'bc-3', title: 'Agent 3', status: 'Archived'),
      ws.WidgetAgent(id: 'bc-4', title: 'Agent 4', status: 'Unknown'),
    ]);
    expect(
      state(
        agents: agents,
        preferences: const Preferences(widgetTitles: true),
      ).agentRows(),
      const <ws.WidgetAgent>[
        ws.WidgetAgent(id: 'bc-1', title: 'Fix login', status: 'Active'),
        ws.WidgetAgent(id: 'bc-2', title: 'Agent 2', status: 'Idle'),
        ws.WidgetAgent(id: 'bc-3', title: 'Agent 3', status: 'Archived'),
        ws.WidgetAgent(id: 'bc-4', title: 'Docs', status: 'Unknown'),
      ],
    );
    expect(
      state(
        agents: agents,
        preferences: chinese.copyWith(widgetTitles: true),
      ).agentRows(),
      const <ws.WidgetAgent>[
        ws.WidgetAgent(id: 'bc-1', title: 'Fix login', status: '活跃'),
        ws.WidgetAgent(id: 'bc-2', title: '会话 2', status: '空闲'),
        ws.WidgetAgent(id: 'bc-3', title: '会话 3', status: '已归档'),
        ws.WidgetAgent(id: 'bc-4', title: 'Docs', status: '未知'),
      ],
    );
  });

  test('agentRows are empty when disconnected or without agents', () {
    expect(state(agents: agents, webConnected: false).agentRows(), isEmpty);
    expect(state().agentRows(), isEmpty);
  });

  test('time formats pad month, day, hour and minute', () {
    final int early = DateTime(2026, 1, 2, 3, 4).millisecondsSinceEpoch;
    expect(ws.WidgetState.formatTime(early), '01-02 03:04');
    expect(ws.WidgetState.formatClock(early), '03:04');
    final int late = DateTime(2026, 12, 31, 23, 59).millisecondsSinceEpoch;
    expect(ws.WidgetState.formatTime(late), '12-31 23:59');
  });
}
