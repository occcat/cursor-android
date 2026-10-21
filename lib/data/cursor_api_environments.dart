part of 'cursor_api.dart';

/// Cloud environment and secret calls of [CursorApi], kept in a part file so
/// later edits stay small. Each call goes through [CursorApi.request].
extension CursorApiEnvironments on CursorApi {
  /// Lists cloud environments: the shared ones, then the personal ones.
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.environments`. Posts `{}` to
  /// `list-environments` and then to `list-personal-environments`, and merges
  /// both `environments` arrays by `publicId`, keeping the first. Items that
  /// are not objects or lack a non-blank string `publicId` are skipped, and a
  /// missing array counts as empty. Nothing is cached. Each call goes through
  /// [request], so an `invalid_csrf_token` failure mints a fresh token and
  /// retries once; a failure of the first call stops before the second.
  Future<List<Map<String, dynamic>>> listEnvironments() async {
    final Map<String, dynamic> shared = await request(
      'POST',
      const <String>['api', 'background-composer', 'list-environments'],
      body: <String, dynamic>{},
    );
    final Map<String, dynamic> personal = await request(
      'POST',
      const <String>[
        'api',
        'background-composer',
        'list-personal-environments',
      ],
      body: <String, dynamic>{},
    );
    final Set<String> seen = <String>{};
    final List<Map<String, dynamic>> merged = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> response in <Map<String, dynamic>>[
      shared,
      personal,
    ]) {
      final Object? environments = response['environments'];
      if (environments is! List) {
        continue;
      }
      for (final Object? item in environments) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final Object? id = item['publicId'];
        if (id is String && id.trim().isNotEmpty && seen.add(id)) {
          merged.add(item);
        }
      }
    }
    return merged;
  }

  /// Fetches one cloud environment with its `environment.json` as text.
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.environment`. Posts the
  /// trimmed [publicId] with `includeEnvironmentJson: true`, reads the nested
  /// `environment` object (or the response itself) and returns `publicId`
  /// (the requested id when blank), `name` and `environmentJson`. Nothing is
  /// cached. Goes through [request], so an `invalid_csrf_token` failure mints
  /// a fresh token and retries once. A blank [publicId] throws an
  /// [ArgumentError] before any network call.
  Future<Map<String, dynamic>> getEnvironment(String publicId) async {
    final String id = publicId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(publicId, 'publicId', 'must not be blank');
    }
    final Map<String, dynamic> response = await request(
      'POST',
      const <String>['api', 'background-composer', 'get-environment'],
      body: <String, dynamic>{
        'publicId': id,
        'includeEnvironmentJson': true,
      },
    );
    final Object? nested = response['environment'];
    final Map<dynamic, dynamic> environment = nested is Map ? nested : response;
    final String found = _primitiveText(environment['publicId']);
    return <String, dynamic>{
      'publicId': found.trim().isEmpty ? id : found,
      'name': _primitiveText(environment['name']),
      'environmentJson': _environmentJsonText(environment['environmentJson']),
    };
  }

  /// Lists redacted secret metadata without persisting it.
  ///
  /// Ported from Kotlin `CursorRepository.secrets`. Removes the exact keys
  /// `value` and `secretValue` and copies the remaining fields as primitive
  /// text; nested objects, arrays and null become empty strings rather than
  /// exposing raw nested payloads. Uses [request] for the existing CSRF retry.
  Future<List<Map<String, dynamic>>> listSecrets() async {
    final Map<String, dynamic> response = await request(
      'POST',
      const <String>[
        'api',
        'background-composer',
        'list-background-composer-secrets',
      ],
      body: <String, dynamic>{'redact': true},
    );
    final Object? secrets = response['secrets'];
    if (secrets is! List) {
      return <Map<String, dynamic>>[];
    }
    return <Map<String, dynamic>>[
      for (final Object? secret in secrets)
        if (secret is Map<String, dynamic>)
          <String, dynamic>{
            for (final MapEntry<String, dynamic> entry in secret.entries)
              if (entry.key != 'value' && entry.key != 'secretValue')
                entry.key: _primitiveText(entry.value),
          },
    ];
  }

  /// Stores the secret [name] with [value], asking the server to redact it.
  ///
  /// Ported from Kotlin `CursorRepository.putSecret`. Posts the trimmed
  /// [name], the exact [value] and `redact: true`, and discards the response.
  /// Nothing is cached and [value] is never put in an error. Uses [request]
  /// for the existing CSRF retry. A blank [name] throws an [ArgumentError]
  /// before any network call.
  Future<void> putSecret(String name, String value) async {
    final String key = name.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be blank');
    }
    await request(
      'POST',
      const <String>[
        'api',
        'background-composer',
        'create-background-composer-secret',
      ],
      body: <String, dynamic>{'name': key, 'value': value, 'redact': true},
    );
  }
}

/// `environment.json` as text, ported from Kotlin 0.1.5
/// `environmentJsonText`: null is empty, a primitive keeps its content and an
/// object or array becomes compact JSON.
String _environmentJsonText(Object? element) {
  if (element == null) {
    return '';
  }
  if (element is String || element is num || element is bool) {
    return '$element';
  }
  return jsonEncode(element);
}
