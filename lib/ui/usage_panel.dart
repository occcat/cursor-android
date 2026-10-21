/// Usage detail content for the sheet, ported from Kotlin 0.1.5
/// `UsagePanel` in `CursorApp.kt`.
library;

import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:cursor_android/ui/cursor_colors.dart';
import 'package:cursor_android/ui/usage_capsule.dart';
import 'package:cursor_android/ui/usage_progress.dart';
import 'package:flutter/material.dart';

/// Local `yyyy-MM-dd HH:mm` for epoch milliseconds [epochMs].
String formatUsageTime(int epochMs) {
  final DateTime time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// Both usage pools with bars and pace hints, snapshot times, reset and
/// pause notices, and a Refresh button that is disabled while disconnected.
class UsagePanel extends StatelessWidget {
  const UsagePanel({
    super.key,
    required this.usage,
    required this.preferences,
    required this.connected,
    this.onRefresh,
    this.nowMs,
  });

  final UsageSnapshot? usage;
  final Preferences preferences;

  /// Whether a web session is connected; Refresh is disabled otherwise.
  final bool connected;

  final VoidCallback? onRefresh;

  /// Current time in epoch milliseconds; defaults to the clock.
  final int? nowMs;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final int now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final UsageSnapshot? snapshot = usage;
    final List<Widget> children = <Widget>[
      Text('Cursor Usage', style: theme.textTheme.headlineSmall),
      Text(
        connected
            ? 'Account quota · last successful snapshot'
            : 'Connect a web session in Settings to view usage.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      for (final bool cursor in const <bool>[true, false])
        if (cursor ? preferences.cursor : preferences.other)
          _PoolSection(
            cursor: cursor,
            usage: snapshot,
            preferences: preferences,
            nowMs: now,
            note: note,
          ),
      if (snapshot != null) ...<Widget>[
        const Divider(height: 1),
        Text('Updated ${formatUsageTime(snapshot.fetchedAt)}', style: note),
        if (!snapshot.unlimited && snapshot.cycleEnd != null)
          Text('Resets ${formatUsageTime(snapshot.cycleEnd!)}', style: note),
        if (snapshot.pendingReset(now))
          const Text('Awaiting new billing cycle data'),
      ],
      if (preferences.paused) const Text('Automatic refresh paused'),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: connected ? onRefresh : null,
          child: const Text('Refresh usage'),
        ),
      ),
      Text(
        'Background updates are scheduled by Android, '
        'at least 15 minutes apart.',
        style: note,
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _spaced(children, 20),
      ),
    );
  }
}

/// One pool: dot, name and value, mode note, bar and optional pace note.
class _PoolSection extends StatelessWidget {
  const _PoolSection({
    required this.cursor,
    required this.usage,
    required this.preferences,
    required this.nowMs,
    required this.note,
  });

  final bool cursor;
  final UsageSnapshot? usage;
  final Preferences preferences;
  final int nowMs;
  final TextStyle? note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tint = cursor
        ? poolCursorColor(theme.brightness)
        : poolOtherColor(theme.brightness);
    final UsageSnapshot? snapshot = usage;
    final double? value = snapshot?.value(
      cursor: cursor,
      remaining: preferences.remaining,
    );
    final List<Widget> children = <Widget>[
      Row(
        children: <Widget>[
          UsageDot(color: tint),
          const SizedBox(width: 8),
          Expanded(child: Text(cursor ? 'Cursor Model' : 'Other Model')),
          Text(
            usageValue(
              snapshot,
              cursor: cursor,
              remaining: preferences.remaining,
            ),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'monospace',
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      Text(preferences.remaining ? 'Remaining' : 'Used', style: note),
    ];
    if (snapshot != null && value != null && !snapshot.unlimited) {
      children.add(UsageProgress(value: value / 100, color: tint));
      final Pace? pace = preferences.pace ? snapshot.pace(nowMs) : null;
      if (pace != null) {
        final double? raw = cursor ? snapshot.cursorUsed : snapshot.otherUsed;
        final String text = switch (pace.category(raw ?? 0.0)) {
          1 => 'Faster than billing pace',
          -1 => 'Slower than billing pace',
          _ => 'On pace',
        };
        children.add(
          Text(
            pace.estimated ? '$text · estimated cycle' : text,
            style: note,
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _spaced(children, 8),
    );
  }
}

/// [children] with a [gap]-high space between neighbours.
List<Widget> _spaced(List<Widget> children, double gap) {
  return <Widget>[
    for (int index = 0; index < children.length; index++) ...<Widget>[
      if (index > 0) SizedBox(height: gap),
      children[index],
    ],
  ];
}
