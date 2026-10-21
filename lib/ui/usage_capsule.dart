/// Compact usage summary, ported from Kotlin 0.1.5 `UsageCapsule` in
/// `CursorApp.kt`.
library;

import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:cursor_android/ui/cursor_colors.dart';
import 'package:flutter/material.dart';

/// Display text for one pool: `∞` when unlimited, a truncated whole percent,
/// or `—` when unknown.
String usageValue(
  UsageSnapshot? snapshot, {
  required bool cursor,
  required bool remaining,
}) {
  if (snapshot?.unlimited ?? false) {
    return '∞';
  }
  final double? value = snapshot?.value(cursor: cursor, remaining: remaining);
  return value == null ? '—' : '${value.toInt()}%';
}

/// Rounded, tappable summary of the visible usage pools.
///
/// Renders nothing when both pools are hidden. Only the pool markers are
/// tinted, so the text stays readable and identical for tests and TalkBack.
class UsageCapsule extends StatelessWidget {
  const UsageCapsule({
    super.key,
    required this.usage,
    required this.preferences,
    this.onTap,
  });

  final UsageSnapshot? usage;
  final Preferences preferences;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!preferences.cursor && !preferences.other) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String mode = preferences.remaining ? 'remaining' : 'used';
    final TextStyle figures = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          color: scheme.onSurface,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (preferences.cursor)
                _Pool(
                  marker: '●',
                  tint: poolCursorColor(theme.brightness),
                  name: 'Cursor',
                  value: usageValue(
                    usage,
                    cursor: true,
                    remaining: preferences.remaining,
                  ),
                  mode: mode,
                  style: figures,
                ),
              if (preferences.other)
                _Pool(
                  marker: '○',
                  tint: poolOtherColor(theme.brightness),
                  name: 'Other',
                  value: usageValue(
                    usage,
                    cursor: false,
                    remaining: preferences.remaining,
                  ),
                  mode: mode,
                  style: figures,
                ),
              Text(
                mode,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One pool: a tinted marker followed by `name value` in the text color.
class _Pool extends StatelessWidget {
  const _Pool({
    required this.marker,
    required this.tint,
    required this.name,
    required this.value,
    required this.mode,
    required this.style,
  });

  final String marker;
  final Color tint;
  final String name;
  final String value;
  final String mode;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$name Model $value $mode',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: marker,
              style: TextStyle(color: tint),
            ),
            TextSpan(text: ' $name $value'),
          ],
        ),
        style: style,
      ),
    );
  }
}
