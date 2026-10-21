/// Agent status dot and label, ported from Kotlin 0.1.5 `AgentStatus` in
/// `CursorComponents.kt`.
library;

import 'package:cursor_android/ui/cursor_colors.dart';
import 'package:cursor_android/ui/usage_progress.dart';
import 'package:flutter/material.dart';

/// Dot color for an API [status] string on a [brightness] background.
Color agentStatusColor(String status, Brightness brightness) {
  return switch (status) {
    'RUNNING' || 'CREATING' => cursorAccent,
    'FINISHED' => successColor(brightness),
    'ERROR' || 'FAILED' || 'EXPIRED' => errorColor(brightness),
    'ARCHIVED' => textTertiaryColor(brightness),
    _ => poolOtherColor(brightness),
  };
}

/// A 6 dp status dot followed by the [status] string, shown verbatim.
class AgentStatus extends StatelessWidget {
  const AgentStatus({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        UsageDot(color: agentStatusColor(status, theme.brightness)),
        const SizedBox(width: 6),
        Text(
          status,
          style: theme.textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
        ),
      ],
    );
  }
}
