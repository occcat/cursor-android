/// User display and refresh preferences, ported from Kotlin 0.1.5
/// `Preferences` in `Storage.kt`.
library;

/// Settings that shape the usage capsule, sheet, overlay and widgets.
///
/// Defaults match Kotlin's DataStore fallbacks.
class Preferences {
  const Preferences({
    this.remaining = true,
    this.cursor = true,
    this.other = true,
    this.pace = true,
    this.paused = false,
    this.notifications = false,
    this.intervalSeconds = 60,
    this.language = 'en',
    this.widgetTitles = false,
  });

  /// Show remaining quota instead of used quota.
  final bool remaining;

  /// Show the Cursor (auto) pool.
  final bool cursor;

  /// Show the other (API) pool.
  final bool other;

  /// Show billing-cycle pace hints.
  final bool pace;

  /// Pause automatic usage refresh.
  final bool paused;

  /// Post usage notifications.
  final bool notifications;

  /// Foreground refresh interval: 30, 60, 120 or 300 seconds.
  final int intervalSeconds;

  /// `en` or `zh-CN`.
  final String language;

  /// Show titles on home-screen widgets.
  final bool widgetTitles;

  /// A copy with the given fields replaced.
  Preferences copyWith({
    bool? remaining,
    bool? cursor,
    bool? other,
    bool? pace,
    bool? paused,
    bool? notifications,
    int? intervalSeconds,
    String? language,
    bool? widgetTitles,
  }) {
    return Preferences(
      remaining: remaining ?? this.remaining,
      cursor: cursor ?? this.cursor,
      other: other ?? this.other,
      pace: pace ?? this.pace,
      paused: paused ?? this.paused,
      notifications: notifications ?? this.notifications,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      language: language ?? this.language,
      widgetTitles: widgetTitles ?? this.widgetTitles,
    );
  }
}
