/// Riverpod state for the Inbox agent list.
///
/// The first page of `background-composer/list` loads with no offset.
/// [InboxAgentsNotifier.loadMore] fetches the next page with the last
/// response's `nextPageOffset` and appends it. [InboxAgentsNotifier.refresh]
/// drops the loaded pages and loads the first page again. Whether archived
/// agents are requested follows [inboxIncludeArchivedProvider], which the
/// Include archived filter sets; changing it reloads the first page. Agents can
/// be archived and restored from the list.
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
    this.actionBcId,
  });

  /// Agents from every loaded page, in API order, each non-blank `bcId`
  /// once.
  final List<AgentSummary> agents;

  /// User-facing text for a failed load or action. It never carries cookies
  /// or other secrets.
  final String? errorMessage;

  /// Whether the last page reported more agents along with a
  /// [nextPageOffset].
  final bool hasMore;

  /// The last page's `nextPageOffset`, sent back unchanged as
  /// `last_message_activity_at_ms_offset`; null when [hasMore] is false.
  final Object? nextPageOffset;

  /// Whether the next page is being fetched.
  final bool loadingMore;

  /// The `bcId` being archived or restored, or null when none is.
  final String? actionBcId;

  /// Whether [InboxAgentsNotifier.loadMore] would fetch a page now.
  bool get canLoadMore =>
      hasMore && nextPageOffset != null && !loadingMore && actionBcId == null;

  @override
  String toString() =>
      'InboxAgents(agents: ${agents.length}, hasMore: $hasMore, '
      'loadingMore: $loadingMore, action: ${actionBcId != null}, '
      'error: ${errorMessage != null})';
}

/// Safe Inbox text for a failed agent list load.
///
/// An HTTP 401 or a missing cookie asks the user to reconnect. Other
/// [ApiFailure]s show the status and the already sanitized code, and a
/// [CursorNetworkFailure] shows only the Dio error kind. Anything else, and
/// any text that still looks secret, becomes [genericInboxError].
String inboxAgentsErrorMessage(Object error) =>
    inboxActionErrorMessage(error, action: 'load agents');

/// Safe Inbox text for a failed [action], for example `archive the agent`,
/// with the same rules as [inboxAgentsErrorMessage].
String inboxActionErrorMessage(Object error, {required String action}) {
  final String message = switch (error) {
    ApiFailure(status: 401) ||
    ApiFailure(code: 'connection_required') => inboxReconnectError,
    ApiFailure(:final int status, :final String code) =>
      'Could not $action (HTTP $status · $code).',
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

/// One page of `background-composer/list` for the Inbox.
///
/// The body is the Kotlin 0.1.5 list body from
/// `CursorApi.listBackgroundComposers`, except that `include_archived`
/// follows [includeArchived] so the server does the archived filtering. A
/// non-null [offset] is sent unchanged as
/// `last_message_activity_at_ms_offset`. Goes through `CursorApi.request`,
/// so an `invalid_csrf_token` failure mints a fresh token and retries once.
Future<Map<String, dynamic>> listInboxPage(
  CursorApi api, {
  required bool includeArchived,
  Object? offset,
}) {
  return api.request(
    'POST',
    const <String>['api', 'background-composer', 'list'],
    body: <String, dynamic>{
      'n': 50,
      'include_status': true,
      'include_archived': includeArchived,
      'include_pinned_state': true,
      'last_message_activity_at_ms_offset': ?offset,
    },
  );
}

/// Whether the Inbox asks the server for archived agents too; false until
/// the user turns Include archived on.
class InboxIncludeArchivedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  /// Sets whether archived agents are requested.
  void choose(bool includeArchived) {
    state = includeArchived;
  }
}

/// The Include archived choice; [inboxAgentsProvider] reloads when it
/// changes.
final NotifierProvider<InboxIncludeArchivedNotifier, bool>
inboxIncludeArchivedProvider =
    NotifierProvider<InboxIncludeArchivedNotifier, bool>(
      InboxIncludeArchivedNotifier.new,
    );

/// Loads the first page of Inbox agents, appends later pages, and archives
/// or restores agents.
///
/// The first page comes from [listInboxPage] with no offset and the current
/// [inboxIncludeArchivedProvider] choice. Without a stored web session it
/// resolves to no agents and no error without touching the network. A
/// failed load resolves to an [InboxAgents.errorMessage] instead of an
/// error, so exception text never reaches the UI and Riverpod does not
/// retry the request on its own.
class InboxAgentsNotifier extends AsyncNotifier<InboxAgents> {
  @override
  Future<InboxAgents> build() async {
    final bool includeArchived = ref.watch(inboxIncludeArchivedProvider);
    final Future<bool> connected = ref.watch(webConnectedProvider.future);
    final CursorApi api = ref.watch(cursorApiProvider);
    if (!await connected) {
      return const InboxAgents();
    }
    try {
      return inboxAgentsFromPage(
        await listInboxPage(api, includeArchived: includeArchived),
      );
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
    final bool includeArchived = ref.read(inboxIncludeArchivedProvider);
    final InboxAgents pending = InboxAgents(
      agents: current.agents,
      errorMessage: current.errorMessage,
      hasMore: current.hasMore,
      nextPageOffset: offset,
      loadingMore: true,
    );
    state = AsyncData<InboxAgents>(pending);
    InboxAgents next;
    try {
      final Map<String, dynamic> root = await listInboxPage(
        api,
        includeArchived: includeArchived,
        offset: offset,
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
    _settle(pending, next);
  }

  /// Drops the loaded pages and loads the first page again, with no
  /// offset, through [build].
  ///
  /// Does nothing while the list is loading. The loaded agents stay in the
  /// state until the new first page arrives. A failed refresh resolves to a
  /// safe [InboxAgents.errorMessage], like a failed first load, and a Load
  /// more, archive or restore result that arrives after the refresh is dropped.
  /// The Inbox turns Refresh off while an archive or restore runs.
  void refresh() {
    if (state.isLoading) {
      return;
    }
    ref.invalidateSelf();
  }

  /// Archives the agent [bcId], then reloads the first page.
  Future<void> archive(String bcId) =>
      _setArchived(bcId, archived: true, action: 'archive the agent');

  /// Restores the archived agent [bcId], then reloads the first page.
  Future<void> restore(String bcId) =>
      _setArchived(bcId, archived: false, action: 'restore the agent');

  /// Runs `archiveBackgroundComposer` for [bcId] and reloads the first page
  /// with the current Include archived choice.
  ///
  /// Does nothing for a blank id, while the list or a page is loading, or
  /// while another archive or restore runs. A failed action keeps the list
  /// and skips the reload; a failed reload keeps the list. Either sets a
  /// safe [InboxAgents.errorMessage]. Nothing is retried automatically.
  /// The reload starts again from the first page, so later pages need Load
  /// more again.
  Future<void> _setArchived(
    String bcId, {
    required bool archived,
    required String action,
  }) async {
    if (bcId.trim().isEmpty || state.isLoading || !state.hasValue) {
      return;
    }
    final InboxAgents current = state.requireValue;
    if (current.loadingMore || current.actionBcId != null) {
      return;
    }
    final CursorApi api = ref.read(cursorApiProvider);
    final bool includeArchived = ref.read(inboxIncludeArchivedProvider);
    final InboxAgents pending = InboxAgents(
      agents: current.agents,
      errorMessage: current.errorMessage,
      hasMore: current.hasMore,
      nextPageOffset: current.nextPageOffset,
      actionBcId: bcId,
    );
    state = AsyncData<InboxAgents>(pending);
    InboxAgents next;
    try {
      if (archived) {
        await api.archiveAgent(bcId);
      } else {
        await api.unarchiveAgent(bcId);
      }
    } on Object catch (error) {
      _settle(
        pending,
        _keep(current, inboxActionErrorMessage(error, action: action)),
      );
      return;
    }
    try {
      next = inboxAgentsFromPage(
        await listInboxPage(api, includeArchived: includeArchived),
      );
    } on Object catch (error) {
      next = _keep(current, inboxAgentsErrorMessage(error));
    }
    _settle(pending, next);
  }

  InboxAgents _keep(InboxAgents current, String errorMessage) {
    return InboxAgents(
      agents: current.agents,
      errorMessage: errorMessage,
      hasMore: current.hasMore,
      nextPageOffset: current.nextPageOffset,
    );
  }

  /// Applies [next] unless the list changed since [pending] was set.
  void _settle(InboxAgents pending, InboxAgents next) {
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
  bool includeArchived,
  bool canArchive,
  String? actionBcId,
});

/// [inboxAgentsProvider] as Inbox inputs.
///
/// `loading` is also true while the next page is fetched, and
/// `canLoadMore` is false then. `canArchive` is true only when the list is
/// loaded and no page, archive or restore is in flight. While disconnected
/// this is no agents, not loading, no error, no more pages and no actions,
/// and [inboxAgentsProvider] is not watched.
InboxAgentsView watchInboxAgents(WidgetRef ref) {
  final bool includeArchived = ref.watch(inboxIncludeArchivedProvider);
  if (!watchWebConnected(ref)) {
    return (
      agents: const <AgentSummary>[],
      loading: false,
      errorMessage: null,
      hasMore: false,
      canLoadMore: false,
      includeArchived: includeArchived,
      canArchive: false,
      actionBcId: null,
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
    includeArchived: includeArchived,
    canArchive:
        !state.isLoading &&
        data != null &&
        !data.loadingMore &&
        data.actionBcId == null,
    actionBcId: data?.actionBcId,
  );
}
