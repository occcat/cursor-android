/// Riverpod state for the Cloud environment page.
///
/// [EnvironmentDetailNotifier] loads one environment with `get-environment`
/// and the redacted runtime values with `list-background-composer-secrets`,
/// and runs the page's Save, add and revoke actions through
/// [cursorApiProvider], reloading both after each action. Secret values are
/// sent once and never kept in this state.
library;

import 'dart:convert';

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/providers/cursor_api_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:cursor_android/ui/inbox_page.dart'
    show genericInboxError, safeInboxError;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown when the stored web session is missing or rejected.
const String environmentReconnectError =
    'Your Cursor web session expired. Reconnect to load this environment.';

/// The loaded environment and runtime values, or a safe error message.
class EnvironmentDetail {
  const EnvironmentDetail({
    this.environment,
    this.secrets = const <Map<String, dynamic>>[],
    this.errorMessage,
    this.busy = false,
  });

  /// `publicId`, `name` and `environmentJson` from
  /// `CursorApiEnvironments.getEnvironment`; null until a load succeeds.
  final Map<String, dynamic>? environment;

  /// Redacted metadata from `CursorApiEnvironments.listSecrets`, without
  /// `value` or `secretValue`.
  final List<Map<String, dynamic>> secrets;

  /// User-facing text for the last failed load or action. It never carries
  /// cookies, tokens or secret values.
  final String? errorMessage;

  /// Whether an action or a refresh is in flight.
  final bool busy;

  @override
  String toString() =>
      'EnvironmentDetail(loaded: ${environment != null}, '
      'secrets: ${secrets.length}, busy: $busy, '
      'error: ${errorMessage != null})';
}

/// Safe Cloud environment text for a failed [action], for example
/// `load this environment` or `save the environment`.
///
/// An HTTP 401 or a missing cookie asks the user to reconnect. Other
/// [ApiFailure]s show the status and the already sanitized code, and a
/// [CursorNetworkFailure] shows only the Dio error kind. Anything else, and
/// any text that still looks secret, becomes [genericInboxError]. [action]
/// must not contain the word secret, which the final check would hide.
String environmentErrorMessage(
  Object error, {
  String action = 'load this environment',
}) {
  final String message = switch (error) {
    ApiFailure(status: 401) ||
    ApiFailure(code: 'connection_required') => environmentReconnectError,
    ApiFailure(:final int status, :final String code) =>
      'Could not $action (HTTP $status · $code).',
    CursorNetworkFailure(:final String kind) =>
      'Could not reach Cursor ($kind). Check your connection.',
    _ => genericInboxError,
  };
  return safeInboxError(message);
}

/// Loads one environment and runs its actions.
///
/// Without a stored web session, or for a blank id, it resolves to nothing
/// loaded and no error without touching the network. A failed load or
/// action resolves to an [EnvironmentDetail.errorMessage] instead of an
/// error, so exception text never reaches the UI and Riverpod does not
/// retry on its own. Actions are never retried automatically.
class EnvironmentDetailNotifier extends AsyncNotifier<EnvironmentDetail> {
  EnvironmentDetailNotifier(this.publicId);

  /// The environment this notifier loads.
  final String publicId;

  @override
  Future<EnvironmentDetail> build() async {
    final Future<bool> connected = ref.watch(webConnectedProvider.future);
    final CursorApi api = ref.watch(cursorApiProvider);
    if (publicId.trim().isEmpty || !await connected) {
      return const EnvironmentDetail();
    }
    return _load(api, const EnvironmentDetail());
  }

  /// The environment, then its runtime values, over [before].
  ///
  /// A failed environment load keeps [before]. A failed list of runtime
  /// values keeps the new environment and the values from [before].
  Future<EnvironmentDetail> _load(
    CursorApi api,
    EnvironmentDetail before,
  ) async {
    final Map<String, dynamic> environment;
    try {
      environment = await api.getEnvironment(publicId);
    } on Object catch (error) {
      return EnvironmentDetail(
        environment: before.environment,
        secrets: before.secrets,
        errorMessage: environmentErrorMessage(error),
      );
    }
    try {
      return EnvironmentDetail(
        environment: environment,
        secrets: await api.listSecrets(),
      );
    } on Object catch (error) {
      return EnvironmentDetail(
        environment: environment,
        secrets: before.secrets,
        errorMessage: environmentErrorMessage(
          error,
          action: 'load runtime values',
        ),
      );
    }
  }

  /// Reloads the environment and its runtime values.
  Future<void> refresh() => _run(null, 'load this environment');

  /// Saves [environmentJson], a JSON object as text, as the environment's
  /// `environment.json`, then reloads.
  ///
  /// The text is sent as the decoded object, like Kotlin 0.1.5. There is no
  /// rename call, so the edited name is not sent.
  Future<void> save(String environmentJson) => _run(
    (CursorApi api) =>
        api.saveEnvironment(publicId, jsonDecode(environmentJson) as Object),
    'save the environment',
  );

  /// Adds the runtime value [name] with [value], then reloads. [value] is
  /// sent once and never stored.
  Future<void> addSecret(String name, String value) => _run(
    (CursorApi api) => api.putSecret(name, value),
    'add the runtime value',
  );

  /// Revokes the runtime value [name], narrowed to [id] when given, then
  /// reloads.
  Future<void> revokeSecret(String name, String? id) => _run(
    (CursorApi api) => api.revokeSecret(name, id: id),
    'delete the runtime value',
  );

  /// Runs [call], when given, then reloads.
  ///
  /// Does nothing while the first load or another action is running. A
  /// failed [call] skips the reload and keeps what is loaded. A result that
  /// arrives after the environment was rebuilt is dropped.
  Future<void> _run(
    Future<void> Function(CursorApi api)? call,
    String action,
  ) async {
    if (state.isLoading || !state.hasValue) {
      return;
    }
    final EnvironmentDetail current = state.requireValue;
    if (current.busy) {
      return;
    }
    final CursorApi api = ref.read(cursorApiProvider);
    final EnvironmentDetail pending = EnvironmentDetail(
      environment: current.environment,
      secrets: current.secrets,
      errorMessage: current.errorMessage,
      busy: true,
    );
    state = AsyncData<EnvironmentDetail>(pending);
    EnvironmentDetail next;
    try {
      if (call != null) {
        await call(api);
      }
      next = await _load(api, current);
    } on Object catch (error) {
      next = EnvironmentDetail(
        environment: current.environment,
        secrets: current.secrets,
        errorMessage: environmentErrorMessage(error, action: action),
      );
    }
    if (!ref.mounted ||
        state.isLoading ||
        !state.hasValue ||
        !identical(state.requireValue, pending)) {
      return;
    }
    state = AsyncData<EnvironmentDetail>(next);
  }
}

/// One environment's state, keyed by `publicId` and dropped when no page
/// shows it.
final environmentDetailProvider = AsyncNotifierProvider.autoDispose
    .family<EnvironmentDetailNotifier, EnvironmentDetail, String>(
      EnvironmentDetailNotifier.new,
    );

/// What the Cloud environment page shows.
typedef EnvironmentDetailView = ({
  bool connected,
  bool loaded,
  bool busy,
  String? name,
  String? environmentJson,
  List<Map<String, dynamic>> secrets,
  String? errorMessage,
});

/// [environmentDetailProvider] for [publicId] as Cloud environment inputs.
///
/// `busy` is also true during the first load. While disconnected nothing
/// is loaded, nothing is busy, there is no error and
/// [environmentDetailProvider] is not watched.
EnvironmentDetailView watchEnvironmentDetail(WidgetRef ref, String publicId) {
  if (!watchWebConnected(ref)) {
    return (
      connected: false,
      loaded: false,
      busy: false,
      name: null,
      environmentJson: null,
      secrets: const <Map<String, dynamic>>[],
      errorMessage: null,
    );
  }
  final AsyncValue<EnvironmentDetail> state = ref.watch(
    environmentDetailProvider(publicId),
  );
  final EnvironmentDetail? data = state.hasValue ? state.requireValue : null;
  final Map<String, dynamic>? environment = data?.environment;
  return (
    connected: true,
    loaded: environment != null,
    busy: state.isLoading || (data?.busy ?? false),
    name: _textOrNull(environment?['name']),
    environmentJson: _textOrNull(environment?['environmentJson']),
    secrets: data?.secrets ?? const <Map<String, dynamic>>[],
    errorMessage: state.hasError ? genericInboxError : data?.errorMessage,
  );
}

String? _textOrNull(Object? value) => value is String ? value : null;
