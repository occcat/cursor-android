/// Riverpod state for the Inbox agent list.
///
/// The first page of `background-composer/list` loads with no offset.
/// [InboxAgentsNotifier.loadMore] fetches the next page with the last
/// response's `nextPageOffset` and appends it. Refresh is left to a later
/// round.
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

/// The loaded Inbox agents and paging state, or a safe error message.
class InboxAgents {
  const InboxAgents({
    this.agents = const <AgentSummary>[],
    this.errorMessage,
    this.hasMore = false,
    this.nextPageOffset,
    this.loadingMore = false,
  });

  /// Agents from every loaded page, in API order, each non-blank `bcId`
  /// once.
  final List<AgentSummary> agents;

  /// User-facing text for a failed load. It never carries cookies or other
  /// secrets.
  final String? errorMessage;

  /// Whether the last page reported more agents along with a
  /// [nextPageOffset].
  final bool hasMore;

  /// The last page's `nextPageOffset`, sent back unchanged as
  /// `last_message_activity_at_ms_offset`; null when [hasMore] is false.
  final Object? nextPageOffset;

  /// Whether the next page is being fetched.
  final bool loadingMore;

  /// Whether [InboxAgentsNotifier.loadMore] would fetch a page now.
  bool get canLoadMore => hasMore && nextPageOffset != null && !loadingMore;

  @override
  String toString() =>
      'InboxAgents(agents: ${agents.length}, hasMore: $hasMore, '
      'loadingMore: $loadingMore, error: ${errorMessage != null})';
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

/// [before] followed by the agents in [page] whose non-blank `bcId` is not
/// already listed. Agents with a blank `bcId` are always kept.
List<AgentSummary> mergeInboxAgents(
  List<AgentSummary> before,
  List<AgentSummary> page,
) {
  final Set<String> seen = <String>{
    for (final AgentSummary agent in before)
      if (agent.bcId.trim().isNotEmpty) agent.bcId,
  };
  final List<AgentSummary> merged = <AgentSummary>[...before];
  for (final AgentSummary agent in page) {
    if (agent.bcId.trim().isEmpty) {
      merged.add(agent);
    } else if (!seen.contains(agent.bcId)) {
      seen.add(agent.bcId);
      merged.add(agent);
    }
  }
  return merged;
}

/// Inbox state after the list response [root]: [before] plus its agents,
/// with paging from its `hasMore` and `nextPageOffset`.
///
/// More pages are offered only when `hasMore` is `true` and
/// `nextPageOffset` is a number or a non-blank string.
InboxAgents inboxAgentsFromPage(
  Map<String, dynamic> root, {
  List<AgentSummary> before = const <AgentSummary>[],
}) {
  final Object? offset = switch (root['nextPageOffset']) {
    final num number => number,
    final String text when text.trim().isNotEmpty => text,
    _ => null,
  };
  final bool more = root['hasMore'] == true && offset != null;
  return InboxAgents(
    agents: mergeInboxAgents(before, agentsFromComposers(root)),
    hasMore: more,
    nextPageOffset: more ? offset : null,
  );
}

/// Loads the first page of Inbox agents and appends later pages.
///
/// The first page comes from `listBackgroundComposers()` with no offset.
/// Without a stored web session it resolves to no agents and no error
/// without touching the network. A failed load resolves to an
/// [InboxAgents.errorMessage] instead of an error, so exception text never
/// reaches the UI and Riverpod does not retry the request on its own.
class InboxAgentsNotifier extends AsyncNotifier<InboxAgents> {
  @override
  Future<InboxAgents> build() async {
    final Future<bool> connected = ref.watch(webConnectedProvider.future);
    final CursorApi api = ref.watch(cursorApiProvider);
    if (!await connected) {
      return const InboxAgents();
    }
    try {
      return inboxAgentsFromPage(await api.listBackgroundComposers());
    } on Object catch (error) {
      return InboxAgents(errorMessage: inboxAgentsErrorMessage(error));
    }
  }

  /// Fetches the page after the loaded ones and appends its agents.
  ///
  /// Does nothing unless [InboxAgents.canLoadMore] and the list is not
  /// loading. A failure keeps the loaded agents and the offset, so Load more
  /// can be tried again, and sets a safe [InboxAgents.errorMessage]. A
  /// result that arrives after the list was rebuilt is dropped.
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasValue) {
      return;
    }
    final InboxAgents current = state.requireValue;
    final Object? offset = current.nextPageOffset;
    if (!current.canLoadMore || offset == null) {
      return;
    }
    final CursorApi api = ref.read(cursorApiProvider);
    final InboxAgents pending = InboxAgents(
      agents: current.agents,
      errorMessage: current.errorMessage,
      hasMore: current.hasMore,
      nextPageOffset: offset,
      loadingMore: true,
    );
    state = AsyncData<InboxAgents>(pending);
    final InboxAgents next;
    try {
      final Map<String, dynamic> root = await api.listBackgroundComposers(
        lastMessageActivityAtMsOffset: offset,
      );
      next = inboxAgentsFromPage(root, before: current.agents);
    } on Object catch (error) {
      next = InboxAgents(
        agents: current.agents,
        errorMessage: inboxAgentsErrorMessage(error),
        hasMore: current.hasMore,
        nextPageOffset: offset,
      );
    }
    if (!ref.mounted ||
        state.isLoading ||
        !state.hasValue ||
        !identical(state.requireValue, pending)) {
      return;
    }
    state = AsyncData<InboxAgents>(next);
  }
}

/// The Inbox agent list: the first page plus any pages appended by
/// [InboxAgentsNotifier.loadMore].
final AsyncNotifierProvider<InboxAgentsNotifier, InboxAgents>
inboxAgentsProvider = AsyncNotifierProvider<InboxAgentsNotifier, InboxAgents>(
  InboxAgentsNotifier.new,
);

/// What the Inbox shows for its agent list.
typedef InboxAgentsView = ({
  List<AgentSummary> agents,
  bool loading,
  String? errorMessage,
  bool hasMore,
  bool canLoadMore,
});

/// [inboxAgentsProvider] as Inbox inputs.
///
/// `loading` is also true while the next page is fetched, and
/// `canLoadMore` is false then. While disconnected this is no agents, not
/// loading, no error and no more pages, and [inboxAgentsProvider] is not
/// watched.
InboxAgentsView watchInboxAgents(WidgetRef ref) {
  if (!watchWebConnected(ref)) {
    return (
      agents: const <AgentSummary>[],
      loading: false,
      errorMessage: null,
      hasMore: false,
      canLoadMore: false,
    );
  }
  final AsyncValue<InboxAgents> state = ref.watch(inboxAgentsProvider);
  final InboxAgents? data = state.hasValue ? state.requireValue : null;
  return (
    agents: data?.agents ?? const <AgentSummary>[],
    loading: state.isLoading || (data?.loadingMore ?? false),
    errorMessage: state.hasError ? genericInboxError : data?.errorMessage,
    hasMore: data?.hasMore ?? false,
    canLoadMore: !state.isLoading && (data?.canLoadMore ?? false),
  );
}
