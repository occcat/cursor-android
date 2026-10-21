/// Home-screen widget presentation, ported from Kotlin 0.1.5 `WidgetState`
/// in `widget/WidgetState.kt`. Values carry no credentials or raw account
/// responses.
library;

import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';

/// One row on the Recent Agents widget.
class WidgetAgent {
  const WidgetAgent({
    required this.id,
    required this.title,
    required this.status,
  });

  /// The agent's `bcId`.
  final String id;
  final String title;

  /// Localized status label.
  final String status;

  @override
  bool operator ==(Object other) =>
      other is WidgetAgent &&
      other.id == id &&
      other.title == title &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, title, status);

  @override
  String toString() => 'WidgetAgent($id, $title, $status)';
}

/// Cached usage, agents, preferences and connection state, turned into
/// widget labels.
class WidgetState {
  const WidgetState({
    this.usage,
    this.agents = const <AgentSummary>[],
    this.agentsUpdatedAtMs,
    this.preferences = const Preferences(),
    this.webConnected = false,
  });

  /// A snapshot older than this, in milliseconds, is stale.
  static const int staleAfterMs = 30 * 60 * 1000;

  final UsageSnapshot? usage;

  /// Cached agents; empty when there are none.
  final List<AgentSummary> agents;

  /// When the agent snapshot was cached, like Kotlin `AgentSnapshot.updatedAt`;
  /// null when there is no snapshot.
  final int? agentsUpdatedAtMs;

  final Preferences preferences;

  /// Whether a cursor.com web session is connected, like `Connections.web`.
  final bool webConnected;

  /// [chinese] when the language is `zh-CN`, otherwise [english].
  String text(String english, String chinese) =>
      preferences.language == 'zh-CN' ? chinese : english;

  String metric() =>
      preferences.remaining ? text('Remaining', '剩余') : text('Used', '已用');

  /// One pool as a rounded percent, `∞` when unlimited, or `—` when unknown.
  String value(bool cursor) {
    final UsageSnapshot? snapshot = usage;
    if (!webConnected || snapshot == null) {
      return '—';
    }
    if (snapshot.unlimited) {
      return '∞';
    }
    final double? percent = snapshot.value(
      cursor: cursor,
      remaining: preferences.remaining,
    );
    return percent == null ? '—' : '${percent.round()}%';
  }

  String usageStatus(int nowMs) {
    final UsageSnapshot? snapshot = usage;
    if (!preferences.cursor && !preferences.other) {
      return text('Pools hidden', '模型用量已隐藏');
    }
    if (!webConnected) {
      return text('Connect web session', '连接网页会话');
    }
    if (snapshot == null) {
      return text('No snapshot yet', '暂无快照');
    }
    if (snapshot.pendingReset(nowMs)) {
      return text('Awaiting reset · cached', '等待重置 · 缓存');
    }
    if (nowMs - snapshot.fetchedAt > staleAfterMs) {
      return text('Stale · ', '已过期 · ') + formatTime(snapshot.fetchedAt);
    }
    if (preferences.paused) {
      return text('Paused · ', '已暂停 · ') + formatTime(snapshot.fetchedAt);
    }
    return text('Updated ', '更新于 ') + formatTime(snapshot.fetchedAt);
  }

  String compactUsageStatus(int nowMs) {
    final UsageSnapshot? snapshot = usage;
    if ((!preferences.cursor && !preferences.other) ||
        !webConnected ||
        snapshot == null) {
      return usageStatus(nowMs);
    }
    final String label = preferences.remaining
        ? text('Left', '剩余')
        : text('Used', '已用');
    final String qualifier = snapshot.pendingReset(nowMs)
        ? text('reset due', '待重置')
        : nowMs - snapshot.fetchedAt > staleAfterMs
        ? text('stale', '已过期')
        : preferences.paused
        ? text('paused', '已暂停')
        : '';
    final String timestamp = qualifier.isEmpty
        ? formatTime(snapshot.fetchedAt)
        : formatClock(snapshot.fetchedAt);
    return <String>[
      label,
      qualifier,
      timestamp,
    ].where((String part) => part.isNotEmpty).join(' · ');
  }

  String agentStatus(int nowMs) {
    final int? updatedAt = agentsUpdatedAtMs;
    if (!webConnected) {
      return text('Sign in', '登录');
    }
    if (updatedAt == null) {
      return text('No snapshot yet', '暂无快照');
    }
    if (nowMs - updatedAt > staleAfterMs) {
      return text('Stale · ', '已过期 · ') + formatTime(updatedAt);
    }
    return text('Updated ', '更新于 ') + formatTime(updatedAt);
  }

  List<WidgetAgent> agentRows() {
    if (!webConnected) {
      return const <WidgetAgent>[];
    }
    return <WidgetAgent>[
      for (int index = 0; index < agents.length; index++)
        WidgetAgent(
          id: agents[index].bcId,
          title: _title(agents[index], index),
          status: _status(agents[index].status),
        ),
    ];
  }

  String _title(AgentSummary agent, int index) {
    final String fallback = '${text('Agent', '会话')} ${index + 1}';
    if (!preferences.widgetTitles || agent.name.trim().isEmpty) {
      return fallback;
    }
    return agent.name;
  }

  String _status(String status) => switch (status) {
    'ACTIVE' => text('Active', '活跃'),
    'IDLE' => text('Idle', '空闲'),
    'ARCHIVED' => text('Archived', '已归档'),
    _ => text('Unknown', '未知'),
  };

  /// [timestampMs] as `MM-dd HH:mm` in the local time zone.
  static String formatTime(int timestampMs) {
    final DateTime local = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${_two(local.month)}-${_two(local.day)} ${formatClock(timestampMs)}';
  }

  /// [timestampMs] as `HH:mm` in the local time zone.
  static String formatClock(int timestampMs) {
    final DateTime local = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    return '${_two(local.hour)}:${_two(local.minute)}';
  }
}

String _two(int value) => value.toString().padLeft(2, '0');
