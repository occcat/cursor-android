/// Home-screen widget data contract: a serializable mirror of [WidgetState]
/// labels that a platform widget (Glance through home_widget) reads later.
/// Pure Dart; no Flutter or platform imports.
///
/// Stable keys written by [WidgetPayload.toHomeWidgetMap]:
/// - `usage.metric`, `usage.status`, `usage.compactStatus`: String labels.
/// - `usage.cursor`, `usage.other`: pool values such as `68%`, `∞` or `—`.
/// - `usage.showCursor`, `usage.showOther`: bool pool visibility.
/// - `usage.fetchedAtMs`: int, 0 without a usage snapshot.
/// - `agents.status`: String; `agents.updatedAtMs`: int or null;
///   `agents.count`: int from 0 to [WidgetPayload.maxAgents].
/// - `agents.<i>.id`, `agents.<i>.title`, `agents.<i>.status` for i in 0..4;
///   slots at or after `agents.count` are written as empty strings.
/// - `prefs.language`, `prefs.remaining`, `prefs.paused`, `conn.web`.
library;

import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/widget_state.dart';

/// The string keys of [WidgetPayload.toHomeWidgetMap].
abstract final class WidgetPayloadKeys {
  static const String usageMetric = 'usage.metric';
  static const String usageStatus = 'usage.status';
  static const String usageCompactStatus = 'usage.compactStatus';
  static const String usageCursor = 'usage.cursor';
  static const String usageOther = 'usage.other';
  static const String usageShowCursor = 'usage.showCursor';
  static const String usageShowOther = 'usage.showOther';
  static const String usageFetchedAtMs = 'usage.fetchedAtMs';
  static const String agentsStatus = 'agents.status';
  static const String agentsUpdatedAtMs = 'agents.updatedAtMs';
  static const String agentsCount = 'agents.count';
  static const String prefsLanguage = 'prefs.language';
  static const String prefsRemaining = 'prefs.remaining';
  static const String prefsPaused = 'prefs.paused';
  static const String connWeb = 'conn.web';

  static String agentId(int index) => 'agents.$index.id';
  static String agentTitle(int index) => 'agents.$index.title';
  static String agentStatus(int index) => 'agents.$index.status';
}

/// Everything the Usage and Recent Agents widgets show, as plain values.
class WidgetPayload {
  const WidgetPayload({
    required this.metricLabel,
    required this.usageStatus,
    required this.compactUsageStatus,
    required this.cursorValue,
    required this.otherValue,
    required this.showCursor,
    required this.showOther,
    required this.agentStatus,
    required this.agents,
    required this.language,
    required this.remaining,
    required this.paused,
    required this.webConnected,
    required this.fetchedAtMs,
    required this.agentsUpdatedAtMs,
  });

  /// Labels computed from [state] at [nowMs]; at most [maxAgents] agents.
  factory WidgetPayload.fromState(WidgetState state, int nowMs) {
    final Preferences preferences = state.preferences;
    return WidgetPayload(
      metricLabel: state.metric(),
      usageStatus: state.usageStatus(nowMs),
      compactUsageStatus: state.compactUsageStatus(nowMs),
      cursorValue: state.value(true),
      otherValue: state.value(false),
      showCursor: preferences.cursor,
      showOther: preferences.other,
      agentStatus: state.agentStatus(nowMs),
      agents: List<WidgetAgent>.unmodifiable(
        state.agentRows().take(maxAgents),
      ),
      language: preferences.language,
      remaining: preferences.remaining,
      paused: preferences.paused,
      webConnected: state.webConnected,
      fetchedAtMs: state.usage?.fetchedAt ?? 0,
      agentsUpdatedAtMs: state.agentsUpdatedAtMs,
    );
  }

  /// Reads [toHomeWidgetMap] output. Missing or mistyped keys fall back to
  /// the disconnected, empty [WidgetState]; this never throws.
  factory WidgetPayload.fromHomeWidgetMap(Map<String, Object?> data) {
    final WidgetPayload empty = WidgetPayload.fromState(const WidgetState(), 0);
    String text(String key, String fallback) {
      final Object? value = data[key];
      return value is String ? value : fallback;
    }

    bool flag(String key, bool fallback) {
      final Object? value = data[key];
      return value is bool ? value : fallback;
    }

    int? whole(String key) {
      final Object? value = data[key];
      return value is int ? value : null;
    }

    final int count = (whole(WidgetPayloadKeys.agentsCount) ?? 0).clamp(
      0,
      maxAgents,
    );
    return WidgetPayload(
      metricLabel: text(WidgetPayloadKeys.usageMetric, empty.metricLabel),
      usageStatus: text(WidgetPayloadKeys.usageStatus, empty.usageStatus),
      compactUsageStatus: text(
        WidgetPayloadKeys.usageCompactStatus,
        empty.compactUsageStatus,
      ),
      cursorValue: text(WidgetPayloadKeys.usageCursor, empty.cursorValue),
      otherValue: text(WidgetPayloadKeys.usageOther, empty.otherValue),
      showCursor: flag(WidgetPayloadKeys.usageShowCursor, empty.showCursor),
      showOther: flag(WidgetPayloadKeys.usageShowOther, empty.showOther),
      agentStatus: text(WidgetPayloadKeys.agentsStatus, empty.agentStatus),
      agents: List<WidgetAgent>.unmodifiable(<WidgetAgent>[
        for (int index = 0; index < count; index++)
          WidgetAgent(
            id: text(WidgetPayloadKeys.agentId(index), ''),
            title: text(WidgetPayloadKeys.agentTitle(index), ''),
            status: text(WidgetPayloadKeys.agentStatus(index), ''),
          ),
      ]),
      language: text(WidgetPayloadKeys.prefsLanguage, empty.language),
      remaining: flag(WidgetPayloadKeys.prefsRemaining, empty.remaining),
      paused: flag(WidgetPayloadKeys.prefsPaused, empty.paused),
      webConnected: flag(WidgetPayloadKeys.connWeb, empty.webConnected),
      fetchedAtMs:
          whole(WidgetPayloadKeys.usageFetchedAtMs) ?? empty.fetchedAtMs,
      agentsUpdatedAtMs: whole(WidgetPayloadKeys.agentsUpdatedAtMs),
    );
  }

  /// Rows a widget has room for.
  static const int maxAgents = 5;

  final String metricLabel;
  final String usageStatus;
  final String compactUsageStatus;

  /// The Cursor pool as [WidgetState.value] shows it.
  final String cursorValue;

  /// The other pool as [WidgetState.value] shows it.
  final String otherValue;

  final bool showCursor;
  final bool showOther;
  final String agentStatus;

  /// Agent rows, at most [maxAgents] when built by [WidgetPayload.fromState].
  final List<WidgetAgent> agents;

  final String language;
  final bool remaining;
  final bool paused;
  final bool webConnected;

  /// When usage was fetched, or 0 without a snapshot.
  final int fetchedAtMs;

  /// When agents were cached, or null without a snapshot.
  final int? agentsUpdatedAtMs;

  /// Flat values under [WidgetPayloadKeys], every agent slot included.
  Map<String, Object?> toHomeWidgetMap() {
    final int count = agents.length < maxAgents ? agents.length : maxAgents;
    return <String, Object?>{
      WidgetPayloadKeys.usageMetric: metricLabel,
      WidgetPayloadKeys.usageStatus: usageStatus,
      WidgetPayloadKeys.usageCompactStatus: compactUsageStatus,
      WidgetPayloadKeys.usageCursor: cursorValue,
      WidgetPayloadKeys.usageOther: otherValue,
      WidgetPayloadKeys.usageShowCursor: showCursor,
      WidgetPayloadKeys.usageShowOther: showOther,
      WidgetPayloadKeys.usageFetchedAtMs: fetchedAtMs,
      WidgetPayloadKeys.agentsStatus: agentStatus,
      WidgetPayloadKeys.agentsUpdatedAtMs: agentsUpdatedAtMs,
      WidgetPayloadKeys.agentsCount: count,
      for (int index = 0; index < maxAgents; index++) ...<String, Object?>{
        WidgetPayloadKeys.agentId(index): index < count ? agents[index].id : '',
        WidgetPayloadKeys.agentTitle(index): index < count
            ? agents[index].title
            : '',
        WidgetPayloadKeys.agentStatus(index): index < count
            ? agents[index].status
            : '',
      },
      WidgetPayloadKeys.prefsLanguage: language,
      WidgetPayloadKeys.prefsRemaining: remaining,
      WidgetPayloadKeys.prefsPaused: paused,
      WidgetPayloadKeys.connWeb: webConnected,
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! WidgetPayload || other.agents.length != agents.length) {
      return false;
    }
    for (int index = 0; index < agents.length; index++) {
      if (other.agents[index] != agents[index]) {
        return false;
      }
    }
    return other.metricLabel == metricLabel &&
        other.usageStatus == usageStatus &&
        other.compactUsageStatus == compactUsageStatus &&
        other.cursorValue == cursorValue &&
        other.otherValue == otherValue &&
        other.showCursor == showCursor &&
        other.showOther == showOther &&
        other.agentStatus == agentStatus &&
        other.language == language &&
        other.remaining == remaining &&
        other.paused == paused &&
        other.webConnected == webConnected &&
        other.fetchedAtMs == fetchedAtMs &&
        other.agentsUpdatedAtMs == agentsUpdatedAtMs;
  }

  @override
  int get hashCode => Object.hash(
    metricLabel,
    usageStatus,
    compactUsageStatus,
    cursorValue,
    otherValue,
    showCursor,
    showOther,
    agentStatus,
    Object.hashAll(agents),
    language,
    remaining,
    paused,
    webConnected,
    fetchedAtMs,
    agentsUpdatedAtMs,
  );

  @override
  String toString() => 'WidgetPayload(${toHomeWidgetMap()})';
}
