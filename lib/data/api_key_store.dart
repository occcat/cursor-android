import 'package:cursor_android/data/credentials.dart';

/// Persists the Cursor API key through [Credentials].
///
/// The key is never logged or included in [toString].
class ApiKeyStore {
  const ApiKeyStore(this.credentials);

  final Credentials credentials;

  /// Returns the saved key, or `null` when none is stored.
  Future<String?> readApiKey() async {
    final String? key = await credentials.read(kApiKeyName);
    return (key == null || key.isEmpty) ? null : key;
  }

  /// Saves [key]. A `null` or empty [key] clears the stored value.
  Future<void> saveApiKey(String? key) {
    final String? value = (key == null || key.isEmpty) ? null : key;
    return credentials.write(kApiKeyName, value);
  }

  @override
  String toString() => 'ApiKeyStore()';
}
