import 'package:cursor_android/widget/widget_home_sync.dart';
import 'package:cursor_android/widget/widget_payload.dart';
import 'package:flutter_test/flutter_test.dart';

WidgetPayload samplePayload({int? agentsUpdatedAtMs}) {
  return WidgetPayload.fromHomeWidgetMap(<String, Object?>{
    WidgetPayloadKeys.usageMetric: 'Usage',
    WidgetPayloadKeys.usageStatus: 'Updated just now',
    WidgetPayloadKeys.usageCursor: '68%',
    WidgetPayloadKeys.usageShowCursor: true,
    WidgetPayloadKeys.usageFetchedAtMs: 1000,
    WidgetPayloadKeys.agentsUpdatedAtMs: agentsUpdatedAtMs,
    WidgetPayloadKeys.agentsCount: 1,
    WidgetPayloadKeys.agentId(0): 'bc-1',
    WidgetPayloadKeys.agentTitle(0): 'Fix login',
    WidgetPayloadKeys.agentStatus(0): 'Running',
    WidgetPayloadKeys.connWeb: true,
  });
}

void main() {
  group('WidgetHomeSync.save', () {
    test('writes every payload key once, in map order', () async {
      final WidgetPayload payload = samplePayload(agentsUpdatedAtMs: 2000);
      final List<MapEntry<String, Object?>> saved =
          <MapEntry<String, Object?>>[];

      await WidgetHomeSync.save(
        payload,
        saver: (String key, Object? value) async {
          saved.add(MapEntry<String, Object?>(key, value));
        },
      );

      final Map<String, Object?> expected = payload.toHomeWidgetMap();
      expect(saved, hasLength(30));
      expect(saved.map((entry) => entry.key).toList(), expected.keys.toList());
      expect(Map<String, Object?>.fromEntries(saved), expected);
      for (final MapEntry<String, Object?> entry in saved) {
        expect(entry.value, anyOf(isA<String>(), isA<bool>(), isA<int>()));
      }
    });

    test('a null agents.updatedAtMs removes the key and round-trips', () async {
      final WidgetPayload payload = samplePayload();
      final Map<String, Object?> store = <String, Object?>{
        WidgetPayloadKeys.agentsUpdatedAtMs: 1234,
      };
      final List<String> nullKeys = <String>[];

      await WidgetHomeSync.save(
        payload,
        saver: (String key, Object? value) async {
          if (value == null) {
            nullKeys.add(key);
            store.remove(key);
          } else {
            store[key] = value;
          }
        },
      );

      expect(nullKeys, <String>[WidgetPayloadKeys.agentsUpdatedAtMs]);
      expect(store.containsKey(WidgetPayloadKeys.agentsUpdatedAtMs), isFalse);
      expect(WidgetPayload.fromHomeWidgetMap(store), payload);
    });

    test('rethrows a saver error and stops writing', () async {
      int calls = 0;

      await expectLater(
        WidgetHomeSync.save(
          samplePayload(),
          saver: (String key, Object? value) async {
            calls++;
            if (calls == 3) {
              throw StateError('storage unavailable');
            }
          },
        ),
        throwsStateError,
      );
      expect(calls, 3);
    });
  });

  group('WidgetHomeSync.update', () {
    test('defaults to the usage receiver', () async {
      final List<String> names = <String>[];

      await WidgetHomeSync.update(
        updater: (String androidName) async {
          names.add(androidName);
        },
      );
      await WidgetHomeSync.update(
        androidName: 'RecentAgentsReceiver',
        updater: (String androidName) async {
          names.add(androidName);
        },
      );

      expect(names, <String>['UsageWidgetReceiver', 'RecentAgentsReceiver']);
      expect(WidgetHomeSync.defaultAndroidName, 'UsageWidgetReceiver');
    });
  });

  group('WidgetHomeSync.sync', () {
    test('saves every value before updating', () async {
      final List<String> log = <String>[];

      await WidgetHomeSync.sync(
        samplePayload(),
        saver: (String key, Object? value) async {
          log.add('save $key');
        },
        updater: (String androidName) async {
          log.add('update $androidName');
        },
      );

      expect(log, hasLength(31));
      expect(log.last, 'update UsageWidgetReceiver');
      expect(log.take(30).every((line) => line.startsWith('save ')), isTrue);
    });
  });
}
