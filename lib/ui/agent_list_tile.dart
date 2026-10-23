/// Inbox agent card, ported from the Kotlin 0.1.5 `Inbox` items in
/// `CursorApp.kt`.
library;

import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/ui/agent_status.dart';
import 'package:cursor_android/ui/usage_panel.dart' show formatUsageTime;
import 'package:flutter/material.dart';

/// Updated text for [agent]: the formatted [AgentSummary.updatedAtMs] when
/// present, otherwise the API's `updatedAt` text.
String agentUpdatedLabel(AgentSummary agent) {
  final int? millis = agent.updatedAtMs;
  return millis != null ? formatUsageTime(millis) : agent.updatedAtLabel;
}

/// A tappable card with the agent name, its status and when it was updated,
/// plus an optional text action such as `Archive`.
class AgentListTile extends StatelessWidget {
  const AgentListTile({
    super.key,
    required this.agent,
    this.onTap,
    this.action,
  });

  final AgentSummary agent;
  final VoidCallback? onTap;

  /// A text button at the end of the card, disabled when its `onPressed` is
  /// null; hidden when [action] is null.
  final ({String label, VoidCallback? onPressed})? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String title = agent.name.trim().isEmpty
        ? 'Untitled agent'
        : agent.name;
    final String updated = agentUpdatedLabel(agent);
    final ({String label, VoidCallback? onPressed})? button = action;
    final Widget details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            AgentStatus(status: agent.status),
            if (updated.isNotEmpty)
              Text(
                updated,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: button == null
              ? details
              : Row(
                  children: <Widget>[
                    Expanded(child: details),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: button.onPressed,
                      child: Text(button.label),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
