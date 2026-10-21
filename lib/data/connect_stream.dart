/// Connect frames and minimal protobuf helpers, ported from Kotlin 0.1.5
/// `ConnectStream.kt` (plus the frame reader from `CursorApi.kt`).
library;

import 'dart:convert';
import 'dart:typed_data';

/// One Connect frame: flag byte, four-byte big-endian length, then payload.
class ConnectFrame {
  const ConnectFrame(this.flags, this.payload);

  final int flags;
  final Uint8List payload;

  /// Whether this is the end-of-stream frame.
  bool get end => (flags & 0x02) != 0;
}

/// One conversation increment decoded from a Connect payload.
class ConversationUpdate {
  const ConversationUpdate(this.offsetKey, this.text, {this.end = false});

  final String? offsetKey;
  final String text;
  final bool end;
}

/// Largest payload [readFrame] accepts, matching Kotlin.
const int maxFramePayload = 8000000;

/// StreamConversation request: field 1 `bcId`, field 2 non-blank offset.
Uint8List encodeConversationRequest(String bcId, String? offsetKey) {
  return _concat(<List<int>>[
    _encodeStringField(1, bcId),
    if (offsetKey != null && offsetKey.trim().isNotEmpty)
      _encodeStringField(2, offsetKey),
  ]);
}

/// Test helper: a data frame carrying one interaction update.
Uint8List interactionFrame(String offset, String text) {
  final Uint8List update = _encodeStringField(1, text);
  final Uint8List wrapped = _concat(<List<int>>[
    _encodeStringField(1, offset),
    _encodeMessageField(2, update),
  ]);
  return envelope(0, _encodeMessageField(4, wrapped));
}

/// Test helper: an end-of-stream frame with a JSON trailer.
Uint8List endFrame([String json = '{}']) =>
    envelope(2, Uint8List.fromList(utf8.encode(json)));

/// Flag byte, four-byte big-endian payload length, then [payload].
Uint8List envelope(int flags, Uint8List payload) {
  final int length = payload.length;
  return _concat(<List<int>>[
    <int>[
      flags & 0xFF,
      (length >>> 24) & 0xFF,
      (length >>> 16) & 0xFF,
      (length >>> 8) & 0xFF,
      length & 0xFF,
    ],
    payload,
  ]);
}

/// Reads one frame from [buffer] at [offset].
///
/// Returns `null` at the end of [buffer]. Throws a [FormatException] for a
/// truncated frame or a length outside `0..maxFramePayload`, like Kotlin's
/// stream reader. The message never includes payload bytes.
({ConnectFrame frame, int next})? readFrame(
  Uint8List buffer, [
  int offset = 0,
]) {
  if (offset >= buffer.length) {
    return null;
  }
  if (buffer.length - offset < 5) {
    throw const FormatException('Truncated frame');
  }
  final ByteData header = ByteData.sublistView(buffer, offset, offset + 5);
  final int flags = header.getUint8(0);
  final int length = header.getInt32(1);
  if (length < 0 || length > maxFramePayload) {
    throw const FormatException('Frame length');
  }
  final int start = offset + 5;
  if (buffer.length - start < length) {
    throw const FormatException('Truncated frame');
  }
  return (
    frame: ConnectFrame(flags, buffer.sublist(start, start + length)),
    next: start + length,
  );
}

/// Decodes a data-frame payload into offset and visible text.
///
/// Field 14 marks a non-text event. Malformed protobuf yields an empty update
/// instead of throwing.
ConversationUpdate decodeConversationPayload(Uint8List payload) {
  final List<_ProtoField> top = _parseProto(payload);
  if (top.any((_ProtoField field) => field.field == 14)) {
    return const ConversationUpdate(null, '');
  }
  final Uint8List? interaction = _firstBytes(top, 4);
  if (interaction == null) {
    return const ConversationUpdate(null, '');
  }
  final List<_ProtoField> inner = _parseProto(interaction);
  final Uint8List? offset = _firstBytes(inner, 1);
  final Uint8List? update = _firstBytes(inner, 2);
  return ConversationUpdate(
    offset == null ? null : _utf8Text(offset),
    update == null ? '' : _collectText(update),
  );
}

final RegExp _hexId = RegExp(r'^[0-9a-fA-F]{32,}$');

/// Bytes of the first [field] entry, which may be `null` for scalars.
Uint8List? _firstBytes(List<_ProtoField> fields, int field) {
  for (final _ProtoField entry in fields) {
    if (entry.field == field) {
      return entry.bytes;
    }
  }
  return null;
}

String _collectText(Uint8List message) {
  final StringBuffer parts = StringBuffer();
  void walk(Uint8List bytes) {
    final List<_ProtoField> fields = _parseProto(bytes);
    for (final _ProtoField field in fields) {
      final Uint8List? raw = field.bytes;
      if (raw == null) {
        continue;
      }
      final String? text = _utf8Text(raw);
      if (text == null) {
        walk(raw);
      } else if (!_hexId.hasMatch(text)) {
        parts.write(text);
      }
    }
  }

  walk(message);
  return parts.toString();
}

class _ProtoField {
  const _ProtoField(this.field, this.bytes);

  final int field;
  final Uint8List? bytes;
}

List<_ProtoField> _parseProto(Uint8List data) {
  const List<_ProtoField> invalid = <_ProtoField>[];
  final List<_ProtoField> out = <_ProtoField>[];
  int index = 0;
  while (index < data.length) {
    final (int, int)? key = _readVarint(data, index);
    if (key == null) {
      return invalid;
    }
    index = key.$2;
    final int field = (key.$1 >>> 3).toSigned(32);
    switch (key.$1 & 7) {
      case 0:
        final (int, int)? value = _readVarint(data, index);
        if (value == null) {
          return invalid;
        }
        index = value.$2;
        out.add(_ProtoField(field, null));
      case 1:
        if (index + 8 > data.length) {
          return invalid;
        }
        index += 8;
        out.add(_ProtoField(field, null));
      case 2:
        final (int, int)? length = _readVarint(data, index);
        if (length == null) {
          return invalid;
        }
        index = length.$2;
        final int size = length.$1.toSigned(32);
        if (size < 0 || index + size > data.length) {
          return invalid;
        }
        out.add(_ProtoField(field, data.sublist(index, index + size)));
        index += size;
      case 5:
        if (index + 4 > data.length) {
          return invalid;
        }
        index += 4;
        out.add(_ProtoField(field, null));
      default:
        return invalid;
    }
  }
  return out;
}

/// Returns the value and the index after it, or `null` if truncated.
(int, int)? _readVarint(Uint8List data, int start) {
  int value = 0;
  int shift = 0;
  int index = start;
  while (index < data.length && shift < 64) {
    final int byte = data[index];
    value |= (byte & 0x7F) << shift;
    index++;
    if ((byte & 0x80) == 0) {
      return (value, index);
    }
    shift += 7;
  }
  return null;
}

Uint8List _encodeStringField(int field, String value) =>
    _encodeMessageField(field, Uint8List.fromList(utf8.encode(value)));

Uint8List _encodeMessageField(int field, Uint8List message) =>
    _concat(<List<int>>[
      _encodeVarint((field << 3) | 2),
      _encodeVarint(message.length),
      message,
    ]);

List<int> _encodeVarint(int value) {
  final List<int> out = <int>[];
  int rest = value;
  while (rest > 0x7F) {
    out.add((rest & 0x7F) | 0x80);
    rest = rest >>> 7;
  }
  out.add(rest & 0xFF);
  return out;
}

/// Decoded text, or `null` for empty, malformed or control-character input.
String? _utf8Text(Uint8List bytes) {
  if (bytes.isEmpty) {
    return null;
  }
  final String text = utf8.decode(bytes, allowMalformed: true);
  if (text.contains('\uFFFD')) {
    return null;
  }
  for (final int unit in text.codeUnits) {
    if (unit < 32 && unit != 0x0A && unit != 0x0D && unit != 0x09) {
      return null;
    }
  }
  return text;
}

Uint8List _concat(List<List<int>> parts) {
  final Uint8List out = Uint8List(
    parts.fold<int>(0, (int total, List<int> part) => total + part.length),
  );
  int index = 0;
  for (final List<int> part in parts) {
    out.setRange(index, index + part.length, part);
    index += part.length;
  }
  return out;
}
