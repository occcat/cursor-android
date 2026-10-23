/// Persistence for [Preferences], ported from Kotlin 0.1.5 `SettingsStore`
/// in `Storage.kt`.
library;

import 'dart:convert';

import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/domain/preferences.dart';

/// Credential name for the stored preferences JSON.
const String kPreferencesName = 'preferences';

const List<int> _intervals = <int>[30, 60, 120, 300];

const List<String> _languages = <String>['en', 'zh-CN'];

/// [preferences] as a JSON object with the Kotlin DataStore key names:
/// `remaining`, `cursor`, `other`, `pace`, `paused`, `notifications`,
/// `interval`, `language` and `widgetTitles`.
Map<String, Object> preferencesToJson(Preferences preferences) {
  return <String, Object>{
    'remaining': preferences.remaining,
    'cursor': preferences.cursor,
    'other': preferences.other,
    'pace': preferences.pace,
    'paused': preferences.paused,
    'notifications': preferences.notifications,
    'interval': preferences.intervalSeconds,
    'language': preferences.language,
    'widgetTitles': preferences.widgetTitles,
  };
}

/// [Preferences] from a decoded [json] value.
///
/// Each field falls back to its default on its own when missing or of the
/// wrong type, like Kotlin's DataStore fallbacks. An `interval` outside 30,
/// 60, 120 and 300, or a `language` other than `en` and `zh-CN`, also falls
/// back. Anything that is not an object yields the defaults.
Preferences preferencesFromJson(Object? json) {
  const Preferences defaults = Preferences();
  if (json is! Map) {
    return defaults;
  }
  bool flag(String key, bool fallback) {
    final Object? value = json[key];
    return value is bool ? value : fallback;
  }

  final Object? interval = json['interval'];
  final Object? language = json['language'];
  return Preferences(
    remaining: flag('remaining', defaults.remaining),
    cursor: flag('cursor', defaults.cursor),
    other: flag('other', defaults.other),
    pace: flag('pace', defaults.pace),
    paused: flag('paused', defaults.paused),
    notifications: flag('notifications', defaults.notifications),
    intervalSeconds: interval is int && _intervals.contains(interval)
        ? interval
        : defaults.intervalSeconds,
    language: language is String && _languages.contains(language)
        ? language
        : defaults.language,
    widgetTitles: flag('widgetTitles', defaults.widgetTitles),
  );
}

/// Reads and writes [Preferences] as one JSON entry in [Credentials].
///
/// Reusing the existing store avoids a new storage dependency. Nothing here
/// is secret; the entry only holds display and refresh choices.
class PreferencesStore {
  const PreferencesStore(this._credentials);

  final Credentials _credentials;

  /// The stored preferences, or the defaults when nothing valid is stored.
  Future<Preferences> read() async {
    final String? text = await _credentials.read(kPreferencesName);
    if (text == null || text.trim().isEmpty) {
      return const Preferences();
    }
    try {
      return preferencesFromJson(jsonDecode(text));
    } on FormatException {
      return const Preferences();
    }
  }

  /// Replaces the stored preferences with [preferences].
  Future<void> write(Preferences preferences) {
    return _credentials.write(
      kPreferencesName,
      jsonEncode(preferencesToJson(preferences)),
    );
  }
}
