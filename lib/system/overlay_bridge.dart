/// Dart side of the `app.cursor.android/overlay` method channel registered by
/// the Android `MainActivity`. It checks and requests the draw-over-other-apps
/// (SYSTEM_ALERT_WINDOW) permission; the floating capsule service is added
/// later.
library;

import 'package:flutter/services.dart';

/// Overlay permission calls. Platform errors, including
/// [MissingPluginException] off Android, are rethrown to the caller.
class OverlayBridge {
  const OverlayBridge({MethodChannel channel = const MethodChannel(channelName)})
    : _channel = channel;

  /// Must match `OVERLAY_CHANNEL` in `MainActivity.kt`.
  static const String channelName = 'app.cursor.android/overlay';

  /// Method returning whether the app may draw over other apps.
  static const String canDrawOverlaysMethod = 'canDrawOverlays';

  /// Method opening the system overlay permission screen for this app.
  static const String openOverlaySettingsMethod = 'openOverlaySettings';

  final MethodChannel _channel;

  /// Whether the app may draw over other apps; a null reply counts as false.
  Future<bool> canDrawOverlays() async {
    final bool? allowed = await _channel.invokeMethod<bool>(
      canDrawOverlaysMethod,
    );
    return allowed ?? false;
  }

  /// Opens the system "display over other apps" screen for this app.
  Future<void> openOverlaySettings() async {
    await _channel.invokeMethod<void>(openOverlaySettingsMethod);
  }
}
