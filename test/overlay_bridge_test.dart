import 'package:cursor_android/system/overlay_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(OverlayBridge.channelName);
  const OverlayBridge bridge = OverlayBridge();
  final List<MethodCall> calls = <MethodCall>[];

  void reply(Object? Function(MethodCall call) answer) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return answer(call);
        });
  }

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('channel name matches MainActivity', () {
    expect(OverlayBridge.channelName, 'app.cursor.android/overlay');
  });

  test('canDrawOverlays returns the platform answer', () async {
    reply((MethodCall call) => true);
    expect(await bridge.canDrawOverlays(), isTrue);

    reply((MethodCall call) => false);
    expect(await bridge.canDrawOverlays(), isFalse);

    expect(
      calls.map((MethodCall call) => call.method).toList(),
      <String>['canDrawOverlays', 'canDrawOverlays'],
    );
  });

  test('canDrawOverlays treats a null reply as not allowed', () async {
    reply((MethodCall call) => null);
    expect(await bridge.canDrawOverlays(), isFalse);
  });

  test('openOverlaySettings invokes the platform method once', () async {
    reply((MethodCall call) => null);
    await bridge.openOverlaySettings();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'openOverlaySettings');
    expect(calls.single.arguments, isNull);
  });

  test('platform errors are rethrown', () async {
    reply(
      (MethodCall call) =>
          throw PlatformException(code: 'unavailable', message: 'none'),
    );

    await expectLater(
      bridge.openOverlaySettings(),
      throwsA(
        isA<PlatformException>().having(
          (PlatformException error) => error.code,
          'code',
          'unavailable',
        ),
      ),
    );
  });

  test('a missing platform handler surfaces MissingPluginException', () async {
    await expectLater(
      bridge.canDrawOverlays(),
      throwsA(isA<MissingPluginException>()),
    );
  });

  test('startOverlay and stopOverlay invoke their platform methods', () async {
    reply((MethodCall call) => null);
    await bridge.startOverlay();
    await bridge.stopOverlay();

    expect(
      calls.map((MethodCall call) => call.method).toList(),
      <String>['startOverlay', 'stopOverlay'],
    );
    expect(calls.every((MethodCall call) => call.arguments == null), isTrue);
  });

  test('startOverlay rethrows a missing permission', () async {
    reply(
      (MethodCall call) =>
          throw PlatformException(code: 'permission', message: 'off'),
    );

    await expectLater(
      bridge.startOverlay(),
      throwsA(
        isA<PlatformException>().having(
          (PlatformException error) => error.code,
          'code',
          'permission',
        ),
      ),
    );
    expect(calls.single.method, 'startOverlay');
  });

  test('method names match MainActivity', () {
    expect(OverlayBridge.startOverlayMethod, 'startOverlay');
    expect(OverlayBridge.stopOverlayMethod, 'stopOverlay');
  });

  test('an injected channel is used instead of the default', () async {
    const MethodChannel other = MethodChannel('test/overlay');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(other, (MethodCall call) async => true);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(other, null);
    });

    expect(await const OverlayBridge(channel: other).canDrawOverlays(), isTrue);
  });
}
