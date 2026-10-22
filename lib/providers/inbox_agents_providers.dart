/// Riverpod providers for the first page of Inbox agents.
///
/// Only the first page of `background-composer/list` is loaded. Paging and
/// merging later pages are left to a later round.
library;

import 'package:cursor_android/data/api_failure.dart';
import 'package:cursor_android/data/cursor_api.dart';
import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/providers/cursor_api_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:cursor_android/ui/inbox_page.dart'
    show genericInboxError, safeInboxError;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown when the stored web session is missing or rejected.
const String inboxReconnectError =
    'Your Cursor web session expired. Reconnect to load agents.';

/// The first page of Inbox agents, or a safe error message.
class InboxAgents {
  const InboxAgents({this.agents = const <AgentSummary>[], this.errorMessage});

  /// Agents from the first page, in API order.
  final List<AgentSummary> agents;

  /// User-facing text for a failed load. It never carries cookies or other
  /// secrets.
  final String? errorMessage;

  @override
  String toString() =>
      'InboxAgents(agents: ${agents.length}, error: ${errorMessage != null})';
}

/// Safe Inbox text for a failed agent list load.
///
/// An HTTP 401 or a missing cookie asks the user to reconnect. Other
/// [ApiFailure]s show the status and the already sanitized code, and a
/// [CursorNetworkFailure] shows only the Dio error kind. Anything else, and
/// any text that still looks secret, becomes [genericInboxError].
String inboxAgentsErrorMessage(Object error) {
  final String message = switch (error) {
    ApiFailure(status: 401) ||
    ApiFailure(code: 'connection_required') => inboxReconnectError,
    ApiFailure(:final int status, :final String code) =>
      'Could not load agents (HTTP $status · $code).',
    CursorNetworkFailure(:final String kind) =>
      'Could not reach Cursor ($kind). Check your connection.',
    _ => genericInboxError,
  };
  return safeInboxError(message);
}

/// The first page of agents from `listBackgroundComposers()`, with no
/// offset.
///
/// Without a stored web session it resolves to no agents and no error
/// without touching the network. A failed load resolves to an
/// [InboxAgents.errorMessage] instead of an error, so exception text never
/// reaches the UI and Riverpod does not retry the request on its own.
final FutureProvider<InboxAgents> inboxAgentsProvider =
    FutureProvider<InboxAgents>((Ref ref) async {
      final Future<bool> connected = ref.watch(webConnectedProvider.future);
      final CursorApi api = ref.watch(cursorApiProvider);
      if (!await connected) {
        return const InboxAgents();
      }
      try {
        final Map<String, dynamic> root = await api.listBackgroundComposers();
        return InboxAgents(agents: agentsFromComposers(root));
      } on Object catch (error) {
        return InboxAgents(errorMessage: inboxAgentsErrorMessage(error));
      }
    });

/// What the Inbox shows for its agent list.
typedef InboxAgentsView = ({
  List<AgentSummary> agents,
  bool loading,
  String? errorMessage,
});

/// [inboxAgentsProvider] as Inbox inputs.
///
/// While disconnected this is no agents, not loading and no error, and
/// [inboxAgentsProvider] is not watched.
InboxAgentsView watchInboxAgents(WidgetRef ref) {
  if (!watchWebConnected(ref)) {
    return (agents: const <AgentSummary>[], loading: false, errorMessage: null);
  }
  final AsyncValue<InboxAgents> state = ref.watch(inboxAgentsProvider);
  final InboxAgents? data = state.hasValue ? state.requireValue : null;
  return (
    agents: data?.agents ?? const <AgentSummary>[],
    loading: state.isLoading,
    errorMessage: state.hasError ? genericInboxError : data?.errorMessage,
  );
}
