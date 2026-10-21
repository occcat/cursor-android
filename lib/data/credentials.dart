import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credential name for the API key.
///
/// Matches the `"api"` entry used by the Kotlin 0.1.5 `Credentials` store.
const String kApiKeyName = 'api';

/// Reads and writes named secrets. Writing `null` deletes the entry.
abstract class Credentials {
  Future<String?> read(String name);

  Future<void> write(String name, String? value);
}

/// In-memory [Credentials] for tests. [toString] never includes values.
class MemoryCredentials implements Credentials {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String name) async => _values[name];

  @override
  Future<void> write(String name, String? value) async {
    if (value == null) {
      _values.remove(name);
    } else {
      _values[name] = value;
    }
  }

  @override
  String toString() => 'MemoryCredentials(entries: ${_values.length})';
}

/// [Credentials] backed by platform secure storage.
class SecureCredentials implements Credentials {
  SecureCredentials([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String name) => _storage.read(key: name);

  @override
  Future<void> write(String name, String? value) {
    if (value == null) {
      return _storage.delete(key: name);
    }
    return _storage.write(key: name, value: value);
  }

  @override
  String toString() => 'SecureCredentials()';
}
