/// Writes a [WidgetPayload] into home_widget storage and asks the platform to
/// redraw a widget. No UI here; the Glance receiver is added later.
///
/// `agents.updatedAtMs` may be null. It is then passed to
/// `HomeWidget.saveWidgetData` as null, which removes the stored key: a stale
/// timestamp never outlives its snapshot, and
/// [WidgetPayload.fromHomeWidgetMap] reads the missing key back as null.
library;

import 'package:cursor_android/widget/widget_payload.dart';
import 'package:home_widget/home_widget.dart';

/// Stores [value] under [key]; a null [value] removes [key].
typedef WidgetDataSaver = Future<void> Function(String key, Object? value);

/// Asks the platform to redraw the widget whose receiver is [androidName].
typedef WidgetUpdater = Future<void> Function(String androidName);

/// Thin bridge from [WidgetPayload] to home_widget. Errors are rethrown.
abstract final class WidgetHomeSync {
  /// Placeholder name of the Glance receiver added in a later change.
  static const String defaultAndroidName = 'UsageWidgetReceiver';

  /// Saves every [WidgetPayload.toHomeWidgetMap] entry, in map order, through
  /// [saver]. Stops at the first error and rethrows it.
  static Future<void> save(
    WidgetPayload payload, {
    WidgetDataSaver saver = saveWithHomeWidget,
  }) async {
    final Map<String, Object?> data = payload.toHomeWidgetMap();
    for (final MapEntry<String, Object?> entry in data.entries) {
      await saver(entry.key, entry.value);
    }
  }

  /// Redraws [androidName], or [defaultAndroidName], through [updater].
  static Future<void> update({
    String? androidName,
    WidgetUpdater updater = updateWithHomeWidget,
  }) {
    return updater(androidName ?? defaultAndroidName);
  }

  /// Runs [save], then [update] once every value is stored.
  static Future<void> sync(
    WidgetPayload payload, {
    String? androidName,
    WidgetDataSaver saver = saveWithHomeWidget,
    WidgetUpdater updater = updateWithHomeWidget,
  }) async {
    await save(payload, saver: saver);
    await update(androidName: androidName, updater: updater);
  }

  /// Saves [value] with the matching `HomeWidget.saveWidgetData` type.
  /// Throws [ArgumentError] for anything but String, bool, int or null.
  static Future<void> saveWithHomeWidget(String key, Object? value) async {
    switch (value) {
      case null:
        await HomeWidget.saveWidgetData<Object>(key, null);
      case final String text:
        await HomeWidget.saveWidgetData<String>(key, text);
      case final bool flag:
        await HomeWidget.saveWidgetData<bool>(key, flag);
      case final int number:
        await HomeWidget.saveWidgetData<int>(key, number);
      default:
        throw ArgumentError.value(value, key, 'Unsupported widget value type');
    }
  }

  /// Calls `HomeWidget.updateWidget` for [androidName].
  static Future<void> updateWithHomeWidget(String androidName) async {
    await HomeWidget.updateWidget(androidName: androidName);
  }
}
