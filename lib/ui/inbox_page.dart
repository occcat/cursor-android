/// Inbox page, ported from Kotlin 0.1.5 `Inbox` and `FeatureLinks` in
/// `CursorApp.kt`. All data and actions are injected by the caller.
library;

import 'package:cursor_android/domain/agent_summary.dart';
import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/domain/usage_snapshot.dart';
import 'package:cursor_android/ui/agent_list_tile.dart';
import 'package:cursor_android/ui/usage_capsule.dart';
import 'package:flutter/material.dart';

/// Shown instead of an error message that looks like it carries a cookie,
/// token or other secret.
const String genericInboxError = 'Something went wrong. Try again.';

final RegExp _secretLike = RegExp(
  r'cookie|session=|token|secret|authorization|bearer',
  caseSensitive: false,
);

/// [message] unless it looks like it contains secret material, in which case
/// [genericInboxError]. Callers should already pass safe, user-facing text;
/// this is a last line of defence.
String safeInboxError(String message) =>
    _secretLike.hasMatch(message) ? genericInboxError : message;

/// The Inbox: header, usage capsule, connect card or agent list with search,
/// archived filter and paging, plus loading, error and empty states.
class InboxPage extends StatefulWidget {
  const InboxPage({
    super.key,
    required this.webConnected,
    required this.preferences,
    this.loading = false,
    this.busy = false,
    this.errorMessage,
    this.agents = const <AgentSummary>[],
    this.hasMore = false,
    this.usage,
    this.includeArchived = false,
    this.archivingBcId,
    this.onSignIn,
    this.onCreate,
    this.onRefresh,
    this.onLoadMore,
    this.onUsage,
    this.onOpenAgent,
    this.onOpenWeb,
    this.onIncludeArchivedChanged,
    this.onArchive,
    this.onRestore,
  });

  /// Whether a cursor.com web session is connected.
  final bool webConnected;

  /// Whether the first load or a refresh is in flight.
  final bool loading;

  /// Whether an action is running; disables `+ New agent`.
  final bool busy;

  /// User-facing error text. It must not contain cookies or secrets; text
  /// that looks like it does is replaced by [genericInboxError].
  final String? errorMessage;

  /// All loaded agents; the page filters them locally by name.
  final List<AgentSummary> agents;

  /// Whether another page of agents can be loaded.
  final bool hasMore;

  final UsageSnapshot? usage;
  final Preferences preferences;

  /// Whether Include archived is on. Only read when
  /// [onIncludeArchivedChanged] is set; otherwise the page keeps the choice
  /// itself.
  final bool includeArchived;

  /// The `bcId` being archived or restored; its card shows the action as
  /// running.
  final String? archivingBcId;

  final VoidCallback? onSignIn;
  final VoidCallback? onCreate;
  final VoidCallback? onRefresh;
  final VoidCallback? onLoadMore;
  final VoidCallback? onUsage;

  /// Called with the agent's `bcId` when its card is tapped.
  final ValueChanged<String>? onOpenAgent;

  /// Opens Cursor Web; the button is hidden when this is null.
  final VoidCallback? onOpenWeb;

  /// Receives the new Include archived choice, for example to ask the
  /// server for archived agents. When null the chip only filters the loaded
  /// agents locally.
  final ValueChanged<bool>? onIncludeArchivedChanged;

  /// Archives the agent with this `bcId` after the user confirms. Cards of
  /// agents that are not `ARCHIVED` show `Archive` when this is set.
  final ValueChanged<String>? onArchive;

  /// Restores the agent with this `bcId` after the user confirms. Cards of
  /// `ARCHIVED` agents show `Restore` when this is set.
  final ValueChanged<String>? onRestore;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final TextEditingController _query = TextEditingController();
  bool _archived = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _includeArchived => widget.onIncludeArchivedChanged == null
      ? _archived
      : widget.includeArchived;

  void _chooseArchived(bool value) {
    final ValueChanged<bool>? changed = widget.onIncludeArchivedChanged;
    if (changed == null) {
      setState(() => _archived = value);
    } else {
      changed(value);
    }
  }

  Future<void> _confirmArchive(
    String bcId, {
    required bool restore,
    required ValueChanged<String> run,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Confirm agent action'),
        content: Text(restore ? 'Restore this agent?' : 'Archive this agent?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      run(bcId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? secondary = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final TextStyle? note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final String? error = widget.errorMessage;
    final List<Widget> children = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Your work.\nWithin reach.',
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text('Cloud agents, wherever you are.', style: secondary),
        ],
      ),
      if (widget.loading && widget.agents.isNotEmpty)
        const LinearProgressIndicator(minHeight: 2),
      if (error != null)
        Text(
          safeInboxError(error),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
        ),
      if (widget.preferences.cursor || widget.preferences.other)
        Align(
          alignment: Alignment.centerLeft,
          child: UsageCapsule(
            usage: widget.usage,
            preferences: widget.preferences,
            onTap: widget.onUsage,
          ),
        ),
      if (!widget.webConnected) ...<Widget>[
        _ConnectCard(onSignIn: widget.onSignIn, secondary: secondary),
        _FeatureLinks(onOpenWeb: widget.onOpenWeb, secondary: secondary),
      ] else
        ..._connected(secondary),
      Text(
        'Independent community client. Not affiliated with Cursor.',
        style: note,
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < children.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 16),
            children[index],
          ],
        ],
      ),
    );
  }

  /// The card action for [agent]: `Archive` or `Restore` and its callback,
  /// or null when the matching callback is missing.
  ({String label, VoidCallback? onPressed})? _archiveAction(
    AgentSummary agent,
  ) {
    final bool restore = agent.status == 'ARCHIVED';
    final ValueChanged<String>? run = restore
        ? widget.onRestore
        : widget.onArchive;
    if (run == null) {
      return null;
    }
    final String? running = widget.archivingBcId;
    if (running != null && running == agent.bcId) {
      return (label: restore ? 'Restoring…' : 'Archiving…', onPressed: null);
    }
    return (
      label: restore ? 'Restore' : 'Archive',
      onPressed: running != null || agent.bcId.trim().isEmpty
          ? null
          : () => _confirmArchive(agent.bcId, restore: restore, run: run),
    );
  }

  List<Widget> _connected(TextStyle? secondary) {
    final List<AgentSummary> visible = filterAgents(
      widget.agents,
      query: _query.text,
      includeArchived: _includeArchived,
    );
    final ValueChanged<String>? open = widget.onOpenAgent;
    return <Widget>[
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          FilledButton(
            onPressed: widget.busy ? null : widget.onCreate,
            child: const Text('+ New agent'),
          ),
          FilledButton.tonal(
            onPressed: widget.onRefresh,
            child: const Text('Refresh'),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _query,
            onChanged: (String _) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search agents',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilterChip(
            label: const Text('Include archived'),
            selected: _includeArchived,
            onSelected: _chooseArchived,
          ),
        ],
      ),
      if (widget.loading && widget.agents.isEmpty)
        const Center(child: CircularProgressIndicator())
      else if (visible.isEmpty)
        Text('No agents here yet. Start with a task.', style: secondary)
      else
        for (final AgentSummary agent in visible)
          AgentListTile(
            key: ValueKey<String>(
              agent.bcId.trim().isEmpty ? agent.name : agent.bcId,
            ),
            agent: agent,
            onTap: open == null ? null : () => open(agent.bcId),
            action: _archiveAction(agent),
          ),
      if (widget.hasMore)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: widget.onLoadMore,
            child: const Text('Load more'),
          ),
        ),
      _FeatureLinks(onOpenWeb: widget.onOpenWeb, secondary: secondary),
    ];
  }
}

/// Card asking the user to connect a cursor.com web session.
class _ConnectCard extends StatelessWidget {
  const _ConnectCard({required this.onSignIn, required this.secondary});

  final VoidCallback? onSignIn;
  final TextStyle? secondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Connect your workspace', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Sign in with the Cursor web session on this device. '
              'Email codes and GitHub stay in the app.',
              style: secondary,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onSignIn,
              child: const Text('Get started'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Note that web-only features open in the browser.
class _FeatureLinks extends StatelessWidget {
  const _FeatureLinks({required this.onOpenWeb, required this.secondary});

  final VoidCallback? onOpenWeb;
  final TextStyle? secondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final VoidCallback? openWeb = onOpenWeb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Continue on Cursor Web', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Automations, Codebase, Desktop, Terminal and Files open in your '
          'browser.',
          style: secondary,
        ),
        if (openWeb != null) ...<Widget>[
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: openWeb,
            child: const Text('Open Cursor Web ↗'),
          ),
        ],
      ],
    );
  }
}
