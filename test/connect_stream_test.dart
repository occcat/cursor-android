import 'dart:convert';
import 'dart:typed_data';

import 'package:cursor_android/data/connect_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// Length-delimited protobuf field; enough for small test messages.
List<int> field(int number, List<int> bytes) {
  assert(number < 16 && bytes.length < 128);
  return <int>[(number << 3) | 2, bytes.length, ...bytes];
}

List<int> text(String value) => utf8.encode(value);

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

ConnectFrame onlyFrame(Uint8List buffer) {
  final ({ConnectFrame frame, int next})? read = readFrame(buffer);
  expect(read, isNotNull);
  expect(read!.next, buffer.length);
  expect(readFrame(buffer, read.next), isNull);
  return read.frame;
}

void main() {
  group('envelope and readFrame', () {
    test('writes flags and a big-endian length', () {
      expect(envelope(2, bytes(<int>[1, 2, 3])), <int>[2, 0, 0, 0, 3, 1, 2, 3]);
      final Uint8List large = envelope(0, Uint8List(300));
      expect(large.sublist(0, 5), <int>[0, 0, 0, 1, 44]);
      expect(onlyFrame(large).payload, hasLength(300));
    });

    test('round-trips flags and payload', () {
      final ConnectFrame frame = onlyFrame(envelope(3, bytes(<int>[9, 8])));
      expect(frame.flags, 3);
      expect(frame.payload, <int>[9, 8]);
      expect(frame.end, isTrue);
    });

    test('rejects truncated and oversized frames safely', () {
      final Uint8List secret = bytes(text('session=secret'));
      final Uint8List truncated = envelope(0, secret).sublist(0, 8);
      final Uint8List oversized = bytes(<int>[0, 0x7F, 0xFF, 0xFF, 0xFF]);
      for (final Uint8List input in <Uint8List>[
        bytes(<int>[0, 0, 0]),
        truncated,
        oversized,
      ]) {
        expect(
          () => readFrame(input),
          throwsA(
            isA<FormatException>().having(
              (FormatException e) => e.toString(),
              'message',
              isNot(contains('session')),
            ),
          ),
        );
      }
    });
  });

  group('encodeConversationRequest', () {
    test('writes bcId and an optional offset', () {
      expect(encodeConversationRequest('bc-1', 'previous'), <int>[
        ...field(1, text('bc-1')),
        ...field(2, text('previous')),
      ]);
      expect(encodeConversationRequest('bc-1', null), field(1, text('bc-1')));
      expect(encodeConversationRequest('bc-1', '  '), field(1, text('bc-1')));
    });

    test('carries nothing but the given strings', () {
      final String encoded = utf8.decode(
        encodeConversationRequest('bc-1', 'previous'),
        allowMalformed: true,
      );
      expect(encoded, isNot(contains('session=')));
      expect(encoded, isNot(contains('csrf')));
    });
  });

  group('frames and payloads', () {
    test('interactionFrame decodes to text and offset', () {
      final ConnectFrame frame = onlyFrame(interactionFrame('off-1', 'Hello'));
      expect(frame.end, isFalse);
      final ConversationUpdate update = decodeConversationPayload(
        frame.payload,
      );
      expect(update.text, 'Hello');
      expect(update.offsetKey, 'off-1');
      expect(update.end, isFalse);
    });

    test('keeps non-ASCII text', () {
      final ConnectFrame frame = onlyFrame(interactionFrame('o', '你好'));
      expect(decodeConversationPayload(frame.payload).text, '你好');
    });

    test('endFrame sets the end flag and keeps the JSON trailer', () {
      expect(onlyFrame(endFrame()).end, isTrue);
      final ConnectFrame frame = onlyFrame(endFrame('{"error":{}}'));
      expect(frame.end, isTrue);
      expect(utf8.decode(frame.payload), '{"error":{}}');
    });

    test('field 14 yields an empty update', () {
      final Uint8List payload = bytes(<int>[
        ...field(14, text('x')),
        ...field(4, <int>[...field(1, text('off')), ...field(2, text('hi'))]),
      ]);
      final ConversationUpdate update = decodeConversationPayload(payload);
      expect(update.offsetKey, isNull);
      expect(update.text, isEmpty);
    });

    test('collects nested text but skips long hex ids', () {
      final List<int> update = <int>[
        ...field(1, text('deadbeef' * 4)),
        ...field(2, field(1, text('Hi '))),
        ...field(3, text('there')),
        ...field(4, text('abc123')),
      ];
      final Uint8List payload = bytes(
        field(4, <int>[...field(1, text('off')), ...field(2, update)]),
      );
      expect(decodeConversationPayload(payload).text, 'Hi thereabc123');
    });

    test('a control-character offset is dropped', () {
      final Uint8List payload = bytes(
        field(4, <int>[...field(1, <int>[1]), ...field(2, text('ok'))]),
      );
      final ConversationUpdate update = decodeConversationPayload(payload);
      expect(update.offsetKey, isNull);
      expect(update.text, 'ok');
    });

    test('malformed protobuf gives a safe empty update', () {
      for (final List<int> input in <List<int>>[
        <int>[0xFF],
        <int>[0x22, 0x7F, ...text('session=secret')],
        <int>[0x23, 0x00],
        <int>[0x09, 1, 2, 3],
      ]) {
        final ConversationUpdate update = decodeConversationPayload(
          bytes(input),
        );
        expect(update.offsetKey, isNull, reason: '$input');
        expect(update.text, isEmpty, reason: '$input');
      }
    });
  });
}
