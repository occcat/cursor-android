/// Riverpod state for the Agent detail page.
///
/// [AgentDetailNotifier] loads one agent with `get-detailed-composer` and
/// runs the page's Refresh, follow-up, Pause, Archive and Restore actions
/// through [cursorApiProvider], reloading the agent after each action. The
/// conversation stream, artifacts and the Workspace link are left to a
/// later round.
library;

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/providers/cursor_api_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:cursor_android/ui/inbox_page.dart'
    show genericInboxError, safeInboxError;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown when the stored web session is missing or rejected.
const String agentDetailReconnectError =
    'Your Cursor web session expired. Reconnect to load this agent.';

/// The loaded agent and action state, or a safe error message.
class AgentDetail {
  const AgentDetail({
    this.agent,
    this.errorMessage,
    this.busy = false,
    this.pauseUnavailable = false,
  });

  /// The agent from [normalizeComposer]; null until the first load
  /// succeeds.
  final Map<String, dynamic>? agent;

  /// User-facing text for the last failed load or action. It never carries
  /// cookies or other secrets.
  final String? errorMessage;

  /// Whether an action or a refresh is in flight.
  final bool busy;

  /// Whether the last pause response could not say the agent paused.
  final bool pauseUnavailable;

  @override
  String toString() =>
      'AgentDetail(loaded: ${agent != null}, busy: $busy, '
      'pauseUnavailable: $pauseUnavailable, error: ${errorMessage != null})';
}

/// Safe Agent detail text for a failed [action], for example
/// `load this agent` or `pause the agent`.
///
/// An HTTP 401 or a missing cookie asks the user to reconnect. Other
/// [ApiFailure]s show the status and the already sanitized code, and a
/// [CursorNetworkFailure] shows only the Dio error kind. Anything else, and
/// any text that still looks secret, becomes [genericInboxError].
String agentDetailErrorMessage(
  Object error, {
  String action = 'load this agent',
}) {
  final String message = switch (error) {
    ApiFailure(status: 401) ||
    ApiFailure(code: 'connection_required') => agentDetailReconnectError,
    ApiFailure(:final int status, :final String code) =>
      'Could not $action (HTTP $status · $code).',
    CursorNetworkFailure(:final String kind) =>
      'Could not reach Cursor ($kind). Check your connection.',
    _ => genericInboxError,
  };
  return safeInboxError(message);
}

/// One agent from a `get-detailed-composer` response [root], ported from
/// Kotlin 0.1.5 `normalizeComposer`.
///
/// Reads the first object in `composers`, or its nested `composer` object
/// when there is one, and keeps every field. `bcId`, `status` and `name`
/// fall back to the first entry's fields when blank, and `bcId` finally to
/// [bcId]. A response without composers yields just those three fields.
Map<String, dynamic> normalizeComposer(
  String bcId,
  Map<String, dynamic> root,
) {
  Map<String, dynamic>? first;
  final Object? composers = root['composers'];
  if (composers is List) {
    for (final Object? item in composers) {
      if (item is Map<String, dynamic>) {
        first = item;
        break;
      }
    }
  }
  final Object? nested = first?['composer'];
  final Map<String, dynamic> composer = nested is Map<String, dynamic>
      ? nested
      : (first ?? <String, dynamic>{});
  String field(String key) {
    final String own = _scalar(composer[key]);
    return own.trim().isNotEmpty ? own : _scalar(first?[key]);
  }

  final String id = field('bcId');
  return <String, dynamic>{
    ...composer,
    'bcId': id.trim().isEmpty ? bcId : id,
    'status': field('status'),
    'name': field('name'),
  };
}

/// Text of a JSON scalar, like Kotlin `JsonObject.string`; anything else is
/// empty.
String _scalar(Object? value) =>
    value is String ? value : (value is num || value is bool ? '$value' : '');

/// Loads one agent and runs its actions.
///
/// Without a stored web session, or for a blank id, it resolves to no agent
/// and no error without touching the network. A failed load or action
/// resolves to an [AgentDetail.errorMessage] instead of an error, so
/// exception text never reaches the UI and Riverpod does not retry on its
/// own. Actions are never retried automatically.
class AgentDetailNotifier extends AsyncNotifier<AgentDetail> {
  AgentDetailNotifier(this.bcId);

  /// The agent this notifier loads.
  final String bcId;

  @override
  Future<AgentDetail> build() async {
    final Future<bool> connected = ref.watch(webConnectedProvider.future);
    final CursorApi api = ref.watch(cursorApiProvider);
    if (bcId.trim().isEmpty || !await connected) {
      return const AgentDetail();
    }
    try {
      return AgentDetail(agent: await _load(api));
    } on Object catch (error) {
      return AgentDetail(errorMessage: agentDetailErrorMessage(error));
    }
  }

  Future<Map<String, dynamic>> _load(CursorApi api) async {
    final Map<String, dynamic> root = await api.request(
      'POST',
      const <String>['api', 'background-composer', 'get-detailed-composer'],
      body: <String, dynamic>{'bcId': bcId, 'n': 1, 'includeTeamWide': true},
    );
    return normalizeComposer(bcId, root);
  }

  /// Reloads the agent, keeping the loaded one if the reload fails.
  Future<void> refresh() => _run(null, 'load this agent');

  /// Sends [prompt] as a follow-up, then reloads the agent.
  Future<void> followUp(String prompt) => _run(
    (CursorApi api) async {
      await api.addAsyncFollowupBackgroundComposer(bcId: bcId, prompt: prompt);
      return null;
    },
    'send the follow-up',
  );

  /// Pauses the agent, then reloads it. A response that cannot say the
  /// agent paused sets [AgentDetail.pauseUnavailable].
  Future<void> pause() => _run(
    (CursorApi api) => api.pauseBackgroundComposer(bcId),
    'pause the agent',
  );

  /// Archives the agent, then reloads it.
  Future<void> archive() => _run((CursorApi api) async {
    await api.archiveAgent(bcId);
    return null;
  }, 'archive the agent');

  /// Restores the archived agent, then reloads it.
  Future<void> unarchive() => _run((CursorApi api) async {
    await api.unarchiveAgent(bcId);
    return null;
  }, 'restore the agent');

  /// Runs [call], when given, then reloads the agent.
  ///
  /// [call] returns whether a pause took effect, or null for other actions.
  /// Does nothing while the first load or another action is running. A
  /// failed [call] skips the reload and keeps the loaded agent. A result
  /// that arrives after the agent was rebuilt is dropped.
  Future<void> _run(
    Future<bool?> Function(CursorApi api)? call,
    String action,
  ) async {
    if (state.isLoading || !state.hasValue) {
      return;
    }
    final AgentDetail current = state.requireValue;
    if (current.busy) {
      return;
    }
    final CursorApi api = ref.read(cursorApiProvider);
    final AgentDetail pending = AgentDetail(
      agent: current.agent,
      errorMessage: current.errorMessage,
      busy: true,
      pauseUnavailable: current.pauseUnavailable,
    );
    state = AsyncData<AgentDetail>(pending);
    Map<String, dynamic>? agent = current.agent;
    bool pauseUnavailable = current.pauseUnavailable;
    String? error;
    try {
      if (call != null) {
        final bool? paused = await call(api);
        if (paused != null) {
          pauseUnavailable = !paused;
        }
      }
    } on Object catch (failure) {
      error = agentDetailErrorMessage(failure, action: action);
    }
    if (error == null) {
      try {
        agent = await _load(api);
      } on Object catch (failure) {
        error = agentDetailErrorMessage(failure);
      }
    }
    if (!ref.mounted ||
        state.isLoading ||
        !state.hasValue ||
        !identical(state.requireValue, pending)) {
      return;
    }
    state = AsyncData<AgentDetail>(
      AgentDetail(
        agent: agent,
        errorMessage: error,
        pauseUnavailable: pauseUnavailable,
      ),
    );
  }
}

/// One agent's detail state, keyed by `bcId` and dropped when no page
/// shows it.
final agentDetailProvider = AsyncNotifierProvider.autoDispose
    .family<AgentDetailNotifier, AgentDetail, String>(AgentDetailNotifier.new);

/// What the Agent detail page shows.
typedef AgentDetailView = ({
  bool connected,
  Map<String, dynamic>? agent,
  bool busy,
  String? errorMessage,
  bool pauseUnavailable,
});

/// [agentDetailProvider] for [bcId] as Agent detail inputs.
///
/// `busy` is also true during the first load. While disconnected this is
/// no agent, not busy and no error, and [agentDetailProvider] is not
/// watched.
AgentDetailView watchAgentDetail(WidgetRef ref, String bcId) {
  if (!watchWebConnected(ref)) {
    return (
      connected: false,
      agent: null,
      busy: false,
      errorMessage: null,
      pauseUnavailable: false,
    );
  }
  final AsyncValue<AgentDetail> state = ref.watch(agentDetailProvider(bcId));
  final AgentDetail? data = state.hasValue ? state.requireValue : null;
  return (
    connected: true,
    agent: data?.agent,
    busy: state.isLoading || (data?.busy ?? false),
    errorMessage: state.hasError ? genericInboxError : data?.errorMessage,
    pauseUnavailable: data?.pauseUnavailable ?? false,
  );
}
