import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/connect_stream.dart';
import 'package:cursor_android/data/cursor_api_headers.dart';
import 'package:cursor_android/data/cursor_api_url.dart';
import 'package:dio/dio.dart';

part 'cursor_api_environments.dart';

/// Transport failure that keeps only the Dio error kind.
///
/// Dio errors carry the request options, including the Cookie header, so
/// they are never rethrown from [CursorApi].
class CursorNetworkFailure implements Exception {
  const CursorNetworkFailure(this.kind);

  /// The [DioExceptionType] name, for example `connectionTimeout`.
  final String kind;

  @override
  String toString() => 'Network error · $kind';
}

/// JSON and Connect stream client for the cursor.com web session, ported
/// from Kotlin 0.1.5.
///
/// The cookie is sent only to the session origin: production
/// `https://cursor.com`, or [webBase] when [allowConfiguredOrigin] is set for
/// tests. Redirects are never followed and there is never an `Authorization`
/// header.
class CursorApi {
  CursorApi({
    required this.cookie,
    Uri? webBase,
    this.allowConfiguredOrigin = false,
    Dio? dio,
  }) : webBase = webBase ?? Uri.parse('https://cursor.com/'),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 90),
               followRedirects: false,
               validateStatus: _anyStatus,
             ),
           );

  /// Reads the current session cookie.
  final FutureOr<String?> Function() cookie;

  /// Session origin and base path for every request.
  final Uri webBase;

  /// Lets tests send the cookie to a non-production [webBase].
  final bool allowConfiguredOrigin;

  final Dio _dio;
  String? _csrfToken;

  static const List<String> _bodyMethods = <String>[
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  ];

  static const List<String> _conversationSegments = <String>[
    'api',
    'connect-proxy',
    'aiserver.v1.BackgroundComposerService',
    'StreamConversation',
  ];

  static const String _connectType = 'application/connect+proto';

  static final RegExp _safeCode = RegExp(r'^[A-Za-z0-9_.\-]{1,64}$');

  /// Forgets the cached CSRF token, for example after signing out.
  void resetWebSession() {
    _csrfToken = null;
  }

  /// Reads the web settings, or updates them when [patch] is given.
  Future<Map<String, dynamic>> webSettings([Map<String, dynamic>? patch]) {
    final String operation = patch == null ? 'get' : 'update';
    return request('POST', <String>[
      'api',
      'background-composer',
      '$operation-background-composer-user-settings',
    ], body: patch);
  }

  /// Lists one page of background agents.
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.refreshAgents`. Posts `n: 50`
  /// with `include_status`, `include_archived` and `include_pinned_state` set
  /// to true. A non-null [lastMessageActivityAtMsOffset], normally the
  /// previous page's `nextPageOffset` JSON value, is sent unchanged as
  /// `last_message_activity_at_ms_offset` to fetch the next page. Returns the
  /// response object as is; read its agents with `agentsFromComposers`.
  /// Nothing is cached and pages are not merged. Goes through [request], so
  /// an `invalid_csrf_token` failure mints a fresh token and retries once.
  Future<Map<String, dynamic>> listBackgroundComposers({
    Object? lastMessageActivityAtMsOffset,
  }) {
    return request(
      'POST',
      const <String>['api', 'background-composer', 'list'],
      body: <String, dynamic>{
        'n': 50,
        'include_status': true,
        'include_archived': true,
        'include_pinned_state': true,
        'last_message_activity_at_ms_offset': ?lastMessageActivityAtMsOffset,
      },
    );
  }

  /// Archives the agent [bcId], or restores it when [unarchive] is true.
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.action` (`archive` and
  /// `unarchive`). Goes through [request], so an `invalid_csrf_token` failure
  /// mints a fresh token and retries once. A blank [bcId] throws an
  /// [ArgumentError] before any network call.
  Future<Map<String, dynamic>> archiveBackgroundComposer(
    String bcId, {
    bool unarchive = false,
  }) async {
    if (bcId.trim().isEmpty) {
      throw ArgumentError.value(bcId, 'bcId', 'must not be blank');
    }
    return request(
      'POST',
      const <String>['api', 'auth', 'archiveBackgroundComposer'],
      body: <String, dynamic>{'bcId': bcId, if (unarchive) 'unarchive': true},
    );
  }

  /// Archives the agent [bcId].
  Future<Map<String, dynamic>> archiveAgent(String bcId) =>
      archiveBackgroundComposer(bcId);

  /// Restores the archived agent [bcId].
  Future<Map<String, dynamic>> unarchiveAgent(String bcId) =>
      archiveBackgroundComposer(bcId, unarchive: true);

  /// Starts a background agent from a snapshot and returns its `bcId`.
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.create`. The body carries
  /// [bcId] (generated as `bc-` plus 32 random hex digits when null or blank),
  /// the trimmed [prompt] and `expectedScope: personal`. A non-blank [model]
  /// adds `requestedModels`; a non-blank [environment] adds
  /// `environment.publicId`, otherwise the first of [repos] becomes `repoUrl`.
  /// Goes through [request], so an `invalid_csrf_token` failure mints a fresh
  /// token and retries once. A blank [prompt] throws an [ArgumentError]
  /// before any network call.
  Future<String> startBackgroundComposerFromSnapshot({
    required String prompt,
    List<String> repos = const <String>[],
    String model = '',
    String environment = '',
    String? bcId,
  }) async {
    final String text = prompt.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be blank');
    }
    final String given = bcId?.trim() ?? '';
    final String id = given.isEmpty ? newBackgroundComposerId() : given;
    await request(
      'POST',
      const <String>['api', 'auth', 'startBackgroundComposerFromSnapshot'],
      body: <String, dynamic>{
        'bcId': id,
        'prompt': text,
        if (model.trim().isNotEmpty)
          'requestedModels': <Map<String, dynamic>>[
            <String, dynamic>{'modelId': model},
          ],
        if (environment.trim().isNotEmpty)
          'environment': <String, dynamic>{'publicId': environment}
        else if (repos.isNotEmpty)
          'repoUrl': repos.first,
        'expectedScope': 'personal',
      },
    );
    return id;
  }

  /// A new agent id: `bc-` followed by 32 lowercase hex digits from a secure
  /// random source.
  static String newBackgroundComposerId([Random? random]) =>
      _prefixedHexId('bc-', random);

  /// Sends a follow-up [prompt] to the agent [bcId] and returns the response.
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.followUp`. The body carries
  /// the trimmed [bcId], the trimmed [prompt] as both `followup` and
  /// `followupMessage`, [followupId] (generated as `fu-` plus 32 random hex
  /// digits when null or blank) and `expectedScope: personal`. Goes through
  /// [request], so an `invalid_csrf_token` failure mints a fresh token and
  /// retries once. A blank [bcId] or [prompt] throws an [ArgumentError]
  /// before any network call.
  Future<Map<String, dynamic>> addAsyncFollowupBackgroundComposer({
    required String bcId,
    required String prompt,
    String? followupId,
  }) async {
    final String agent = bcId.trim();
    if (agent.isEmpty) {
      throw ArgumentError.value(bcId, 'bcId', 'must not be blank');
    }
    final String text = prompt.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be blank');
    }
    final String given = followupId?.trim() ?? '';
    return request(
      'POST',
      const <String>['api', 'auth', 'addAsyncFollowupBackgroundComposer'],
      body: <String, dynamic>{
        'bcId': agent,
        'followup': text,
        'followupMessage': text,
        'followupId': given.isEmpty ? newFollowupId() : given,
        'expectedScope': 'personal',
      },
    );
  }

  /// A new follow-up id: `fu-` followed by 32 lowercase hex digits from a
  /// secure random source.
  static String newFollowupId([Random? random]) =>
      _prefixedHexId('fu-', random);

  static String _prefixedHexId(String prefix, Random? random) {
    final Random source = random ?? Random.secure();
    final StringBuffer id = StringBuffer(prefix);
    for (int index = 0; index < 16; index++) {
      id.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return id.toString();
  }

  /// Pauses the agent [bcId] and returns whether the response says so.
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.action` (`pause`). Posts the
  /// trimmed [bcId] and returns [pauseExpressed] for the response, so an
  /// empty body yields `false`. Goes through [request], so an
  /// `invalid_csrf_token` failure mints a fresh token and retries once. A
  /// blank [bcId] throws an [ArgumentError] before any network call.
  Future<bool> pauseBackgroundComposer(String bcId) async {
    final String agent = bcId.trim();
    if (agent.isEmpty) {
      throw ArgumentError.value(bcId, 'bcId', 'must not be blank');
    }
    final Map<String, dynamic> response = await request(
      'POST',
      const <String>['api', 'background-composer', 'pause'],
      body: <String, dynamic>{'bcId': agent},
    );
    return pauseExpressed(response);
  }

  /// Lists the artifacts of the agent [bcId].
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.artifacts`. Posts the
  /// trimmed [bcId] and returns the objects in the response's `artifacts`
  /// array. A missing or non-list `artifacts` yields an empty list, and items
  /// that are not objects are skipped. Nothing is cached. Goes through
  /// [request], so an `invalid_csrf_token` failure mints a fresh token and
  /// retries once. A blank [bcId] throws an [ArgumentError] before any
  /// network call.
  Future<List<Map<String, dynamic>>> listArtifacts(String bcId) async {
    final String agent = bcId.trim();
    if (agent.isEmpty) {
      throw ArgumentError.value(bcId, 'bcId', 'must not be blank');
    }
    final Map<String, dynamic> response = await request(
      'POST',
      const <String>['api', 'background-composer', 'list-artifacts'],
      body: <String, dynamic>{'bcId': agent},
    );
    final Object? artifacts = response['artifacts'];
    if (artifacts is! List) {
      return <Map<String, dynamic>>[];
    }
    return <Map<String, dynamic>>[
      for (final Object? item in artifacts)
        if (item is Map<String, dynamic>) item,
    ];
  }

  static const List<String> _artifactFields = <String>[
    'path',
    'absolutePath',
    'name',
  ];

  /// Fetches the content of [artifact] from the agent [bcId].
  ///
  /// Ported from Kotlin 0.1.5 `CursorRepository.artifactBytes`. Posts the
  /// trimmed [bcId] plus each of `path`, `absolutePath` and `name` that is a
  /// non-blank string in [artifact], and returns the response as is; the
  /// caller decodes any `content`. Nothing is cached. Goes through [request],
  /// so an `invalid_csrf_token` failure mints a fresh token and retries once.
  /// A blank [bcId], or an [artifact] without any of those fields, throws an
  /// [ArgumentError] before any network call.
  Future<Map<String, dynamic>> getArtifactBytes({
    required String bcId,
    required Map<String, dynamic> artifact,
  }) async {
    final String agent = bcId.trim();
    if (agent.isEmpty) {
      throw ArgumentError.value(bcId, 'bcId', 'must not be blank');
    }
    final Map<String, dynamic> body = <String, dynamic>{'bcId': agent};
    for (final String field in _artifactFields) {
      final Object? value = artifact[field];
      if (value is String && value.trim().isNotEmpty) {
        body[field] = value;
      }
    }
    if (body.length == 1) {
      throw ArgumentError('artifact needs a path, absolutePath or name');
    }
    return request(
      'POST',
      const <String>['api', 'background-composer', 'get-artifact-bytes'],
      body: body,
    );
  }

  /// Sends one JSON request and returns the response object.
  ///
  /// An `invalid_csrf_token` failure on a non-GET request mints a fresh token
  /// once and retries once. Every other failure propagates unchanged.
  Future<Map<String, dynamic>> request(
    String method,
    List<String> segments, {
    Map<String, dynamic>? body,
    Map<String, String> query = const <String, String>{},
    String? cookieOverride,
  }) async {
    try {
      return await _execute(method, segments, body, query, cookieOverride);
    } on ApiFailure catch (failure) {
      if (failure.code != 'invalid_csrf_token' || method == 'GET') {
        rethrow;
      }
      await _refreshCsrf(cookieOverride);
      return _execute(method, segments, body, query, cookieOverride);
    }
  }

  /// Streams one agent conversation over Connect, calling [onUpdate] for each
  /// data frame and once more with `end: true` when the stream finishes.
  ///
  /// An `invalid_csrf_token` failure mints a fresh token once and reopens the
  /// stream once. Cancelling [cancelToken] aborts the request and the read
  /// promptly with a [CursorNetworkFailure] of kind `cancel`.
  Future<void> conversation(
    String bcId,
    String? offsetKey,
    FutureOr<void> Function(ConversationUpdate update) onUpdate, {
    CancelToken? cancelToken,
  }) async {
    try {
      await _openConversation(bcId, offsetKey, onUpdate, cancelToken);
    } on ApiFailure catch (failure) {
      if (failure.code != 'invalid_csrf_token') {
        rethrow;
      }
      await _refreshCsrf(null);
      await _openConversation(bcId, offsetKey, onUpdate, cancelToken);
    }
  }

  Future<void> _openConversation(
    String bcId,
    String? offsetKey,
    FutureOr<void> Function(ConversationUpdate update) onUpdate,
    CancelToken? cancelToken,
  ) async {
    final Uri url = buildApiUrl(
      webBase: webBase,
      segments: _conversationSegments,
    );
    if (!_allowed(url)) {
      throw const ApiFailure(0, 'origin_rejected');
    }
    final String? credential = await cookie();
    if (credential == null || credential.trim().isEmpty) {
      throw const ApiFailure(401, 'connection_required');
    }
    final Uint8List body = encodeConversationRequest(bcId, offsetKey);
    final Map<String, String> headers = <String, String>{
      ...sessionHeaders(
        url: url,
        credential: credential,
        csrfToken: _csrfToken,
        method: 'POST',
      ),
      'Accept': _connectType,
      'Connect-Protocol-Version': '1',
      Headers.contentLengthHeader: '${body.length}',
    };
    try {
      final Response<ResponseBody> response = await _dio
          .requestUri<ResponseBody>(
            url,
            data: Stream<Uint8List>.value(body),
            cancelToken: cancelToken,
            options: Options(
              method: 'POST',
              headers: headers,
              contentType: _connectType,
              responseType: ResponseType.stream,
              followRedirects: false,
              validateStatus: _anyStatus,
            ),
          );
      final Stream<Uint8List> stream =
          response.data?.stream ?? const Stream<Uint8List>.empty();
      if (!_isSuccessful(response.statusCode ?? 0)) {
        throw _failure(response, await _readText(stream));
      }
      await _readConversation(stream, onUpdate, cancelToken);
    } on DioException catch (error) {
      throw CursorNetworkFailure(error.type.name);
    }
  }

  Future<void> _readConversation(
    Stream<Uint8List> stream,
    FutureOr<void> Function(ConversationUpdate update) onUpdate,
    CancelToken? cancelToken,
  ) async {
    final StreamIterator<Uint8List> chunks = StreamIterator<Uint8List>(stream);
    final Future<bool> cancelled = cancelToken == null
        ? Completer<bool>().future
        : cancelToken.whenCancel.then((DioException _) => false);
    Uint8List buffer = Uint8List(0);
    try {
      while (true) {
        final ({ConnectFrame frame, int next})? ready = _completeFrame(buffer);
        if (ready != null) {
          buffer = buffer.sublist(ready.next);
          if (await _deliver(ready.frame, onUpdate)) {
            return;
          }
          continue;
        }
        final bool more = await Future.any(<Future<bool>>[
          chunks.moveNext(),
          cancelled,
        ]);
        if (cancelToken?.isCancelled ?? false) {
          throw CursorNetworkFailure(DioExceptionType.cancel.name);
        }
        if (!more) {
          if (buffer.isNotEmpty) {
            throw const FormatException('Truncated frame');
          }
          return;
        }
        buffer = _append(buffer, chunks.current);
      }
    } finally {
      unawaited(chunks.cancel());
    }
  }

  /// Handles one frame; returns `true` once the stream has ended.
  Future<bool> _deliver(
    ConnectFrame frame,
    FutureOr<void> Function(ConversationUpdate update) onUpdate,
  ) async {
    if (frame.end) {
      final String? code = endErrorCode(frame.payload);
      if (code != null) {
        throw ApiFailure(
          400,
          _safeCode.hasMatch(code) ? code : 'request_failed',
        );
      }
      await onUpdate(const ConversationUpdate(null, '', end: true));
      return true;
    }
    if ((frame.flags & 0x01) != 0) {
      throw const FormatException('Compressed frame');
    }
    await onUpdate(decodeConversationPayload(frame.payload));
    return false;
  }

  Future<Map<String, dynamic>> _execute(
    String method,
    List<String> segments,
    Map<String, dynamic>? body,
    Map<String, String> query,
    String? cookieOverride,
  ) async {
    final Response<String> response = await _send(
      method,
      segments,
      body,
      query,
      cookieOverride,
    );
    final int status = response.statusCode ?? 0;
    final String text = response.data ?? '';
    if (!_isSuccessful(status)) {
      throw _failure(response, text);
    }
    return _jsonObjectOrFailure(status, text);
  }

  Future<void> _refreshCsrf(String? cookieOverride) async {
    final Response<String> response = await _send(
      'GET',
      const <String>['api', 'csrf-token'],
      null,
      const <String, String>{},
      cookieOverride,
    );
    final int status = response.statusCode ?? 0;
    if (!_isSuccessful(status)) {
      throw _failure(response, response.data ?? '');
    }
    final Uri url = response.realUri;
    if (!_allowed(url)) {
      throw ApiFailure(status, 'invalid_csrf_token');
    }
    final String? token = _csrfFromSetCookie(
      url,
      response.headers['set-cookie'] ?? const <String>[],
    );
    if (token == null) {
      throw ApiFailure(status, 'invalid_csrf_token');
    }
    _csrfToken = token;
  }

  Future<Response<String>> _send(
    String method,
    List<String> segments,
    Map<String, dynamic>? body,
    Map<String, String> query,
    String? cookieOverride,
  ) async {
    final Uri url = buildApiUrl(
      webBase: webBase,
      segments: segments,
      query: query,
    );
    if (!_allowed(url)) {
      throw const ApiFailure(0, 'origin_rejected');
    }
    final String? credential = cookieOverride ?? await cookie();
    if (credential == null || credential.trim().isEmpty) {
      throw const ApiFailure(401, 'connection_required');
    }
    final bool hasBody = _bodyMethods.contains(method);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      ...sessionHeaders(
        url: url,
        credential: credential,
        csrfToken: _csrfToken,
        method: method,
      ),
    };
    try {
      return await _dio.requestUri<String>(
        url,
        data: hasBody ? jsonEncode(body ?? <String, dynamic>{}) : null,
        options: Options(
          method: method,
          headers: headers,
          contentType: hasBody ? 'application/json' : null,
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: _anyStatus,
        ),
      );
    } on DioException catch (error) {
      throw CursorNetworkFailure(error.type.name);
    }
  }

  bool _allowed(Uri url) => cookieAllowed(
    url: url,
    origin: webBase,
    allowConfiguredOrigin: allowConfiguredOrigin,
  );

  ApiFailure _failure(Response<Object?> response, String body) {
    String code = 'request_failed';
    try {
      final Object? decoded = jsonDecode(body);
      final Object? error = decoded is Map ? decoded['error'] : null;
      final Object? value = error is Map ? error['code'] : null;
      if (value is String || value is num || value is bool) {
        final String text = '$value';
        if (_safeCode.hasMatch(text)) {
          code = text;
        }
      }
    } on FormatException {
      // Not JSON: keep request_failed.
    }
    final List<String>? retryAfter = response.headers['retry-after'];
    return ApiFailure(
      response.statusCode ?? 0,
      code,
      (retryAfter == null || retryAfter.isEmpty) ? null : retryAfter.last,
    );
  }
}

bool _anyStatus(int? status) => true;

bool _isSuccessful(int status) => status >= 200 && status < 300;

const List<String> _pauseKeys = <String>[
  'status',
  'paused',
  'composer',
  'bcId',
  'success',
];

/// Whether a pause response says the agent paused, ported from Kotlin 0.1.5
/// `pauseExpressed`.
///
/// An empty object is `false`. A `composers` list holding at least one object
/// is `true`. Otherwise any of `status`, `paused`, `composer`, `bcId` and
/// `success` makes it `true`.
bool pauseExpressed(Map<String, dynamic> json) {
  if (json.isEmpty) {
    return false;
  }
  final Object? composers = json['composers'];
  if (composers is List && composers.any((Object? item) => item is Map)) {
    return true;
  }
  return _pauseKeys.any(json.containsKey);
}

/// The text of a JSON primitive, like Kotlin `JsonObject.string`; null,
/// objects and arrays become empty.
String _primitiveText(Object? value) =>
    value is String || value is num || value is bool ? '$value' : '';

Map<String, dynamic> _jsonObjectOrFailure(int status, String text) {
  if (text.trim().isEmpty) {
    return <String, dynamic>{};
  }
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    decoded = null;
  }
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  throw ApiFailure(status, 'invalid_body');
}

/// The first whole frame at the start of [buffer], or `null` if more bytes
/// are needed. A bad length fails fast instead of waiting forever.
({ConnectFrame frame, int next})? _completeFrame(Uint8List buffer) {
  if (buffer.length < 5) {
    return null;
  }
  final int length = ByteData.sublistView(buffer, 0, 5).getInt32(1);
  if (length < 0 || length > maxFramePayload) {
    throw const FormatException('Frame length');
  }
  if (buffer.length - 5 < length) {
    return null;
  }
  return readFrame(buffer);
}

Uint8List _append(Uint8List head, Uint8List tail) {
  return Uint8List(head.length + tail.length)
    ..setAll(0, head)
    ..setAll(head.length, tail);
}

Future<String> _readText(Stream<Uint8List> stream) async {
  final List<int> bytes = <int>[];
  await for (final Uint8List chunk in stream) {
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// First `csrf-token` or `cursor-csrf-token` cookie valid for [url].
String? _csrfFromSetCookie(Uri url, List<String> values) {
  for (final String header in values) {
    final List<String> parts = header.split(';');
    final int eq = parts.first.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final String name = parts.first.substring(0, eq).trim();
    if (name != 'csrf-token' && name != 'cursor-csrf-token') {
      continue;
    }
    if (!_domainMatches(url.host, parts.skip(1))) {
      continue;
    }
    return parts.first.substring(eq + 1).trim();
  }
  return null;
}

bool _domainMatches(String host, Iterable<String> attributes) {
  for (final String attribute in attributes) {
    final int eq = attribute.indexOf('=');
    if (eq < 0 || attribute.substring(0, eq).trim().toLowerCase() != 'domain') {
      continue;
    }
    String domain = attribute.substring(eq + 1).trim().toLowerCase();
    if (domain.startsWith('.')) {
      domain = domain.substring(1);
    }
    return host == domain || host.endsWith('.$domain');
  }
  return true;
}
