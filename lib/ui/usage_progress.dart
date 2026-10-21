/// Usage bar and pool dot, ported from Kotlin 0.1.5 `CursorProgress` and
/// `Dot` in `CursorComponents.kt`.
library;

import 'package:flutter/material.dart';

/// Track behind the usage bars on the light background (Kotlin `card03`).
const Color usageTrackLight = Color(0xFFE6E5E0);

/// Track behind the usage bars on the dark background (Kotlin `card03`).
const Color usageTrackDark = Color(0xFF26241E);

/// Usage bar track color for [brightness].
Color usageTrackColor(Brightness brightness) =>
    brightness == Brightness.dark ? usageTrackDark : usageTrackLight;

/// A 6 dp rounded bar filled to [value] (0 to 1) in [color].
///
/// Values outside `0..1` and non-finite values are clamped to the bar.
class UsageProgress extends StatelessWidget {
  const UsageProgress({
    super.key,
    required this.value,
    required this.color,
    this.trackColor,
  });

  /// Filled fraction, 0 to 1.
  final double value;

  /// Fill color, usually a pool color.
  final Color color;

  /// Track color; defaults to [usageTrackColor] for the theme brightness.
  final Color? trackColor;

  /// [value] limited to `0..1`, with non-finite values as 0.
  double get fraction =>
      value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(3);
    return Semantics(
      value: '${(fraction * 100).round()}%',
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: trackColor ?? usageTrackColor(Theme.of(context).brightness),
          borderRadius: radius,
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction,
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: radius),
          ),
        ),
      ),
    );
  }
}

/// A 6 dp filled circle in [color].
class UsageDot extends StatelessWidget {
  const UsageDot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
