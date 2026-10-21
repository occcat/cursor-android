/// Agent detail page, ported from Kotlin 0.1.5 `AgentDetail` in
/// `CursorApp.kt`. All data and actions are injected by the caller; the page
/// never calls the network or opens the conversation stream itself.
library;

import 'package:cursor_android/ui/agent_status.dart';
import 'package:cursor_android/ui/inbox_page.dart' show safeInboxError;
import 'package:flutter/material.dart';

/// Statuses in which `Pause` is hidden.
const Set<String> unpausableStatuses = <String>{
  'FINISHED',
  'ERROR',
  'FAILED',
  'EXPIRED',
  'CANCELLED',
  'ARCHIVED',
};

/// Loads the text of an artifact for the viewer; null means there is nothing
/// to show, for example because the request failed.
typedef AgentArtifactOpener =
    Future<String?> Function(Map<String, dynamic> artifact);

/// The first non-blank of `path`, `name` and `absolutePath`, or null when the
/// artifact has none.
String? artifactTitle(Map<String, dynamic> artifact) {
  for (final String field in const <String>['path', 'name', 'absolutePath']) {
    final Object? value = artifact[field];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
  }
  return null;
}

String _text(Object? value) => value is String ? value : '';

enum _AgentAction { pause, archive, unarchive }

/// One agent: name and status, actions, conversation, artifacts and the
/// follow-up composer.
class AgentDetailPage extends StatefulWidget {
  const AgentDetailPage({
    super.key,
    required this.bcId,
    this.agent,
    this.busy = false,
    this.pauseUnavailable = false,
    this.streamText = '',
    this.artifacts = const <Map<String, dynamic>>[],
    this.showArtifacts = false,
    this.errorMessage,
    this.onRefresh,
    this.onOpenWorkspace,
    this.onToggleArtifacts,
    this.onOpenArtifact,
    this.onFollowUp,
    this.onPause,
    this.onArchive,
    this.onUnarchive,
  });

  /// The agent this page shows.
  final String bcId;

  /// The normalized composer. The page shows the loading state until its
  /// `bcId` equals [bcId].
  final Map<String, dynamic>? agent;

  /// Whether an action is running; disables `Send follow-up`.
  final bool busy;

  /// Whether the last pause response could not say the agent paused.
  final bool pauseUnavailable;

  /// Conversation text so far; the card is hidden while it is blank.
  final String streamText;

  /// Listed artifacts; each may carry `path`, `name` or `absolutePath`.
  final List<Map<String, dynamic>> artifacts;

  /// Whether the artifact list is shown.
  final bool showArtifacts;

  /// User-facing error text. Text that looks like it carries a cookie or
  /// secret is replaced by `genericInboxError`.
  final String? errorMessage;

  final VoidCallback? onRefresh;

  /// Opens `https://cursor.com/agents/<bcId>`.
  final VoidCallback? onOpenWorkspace;

  /// Toggles [showArtifacts] and loads the list.
  final VoidCallback? onToggleArtifacts;

  /// Loads an artifact for the viewer dialog.
  final AgentArtifactOpener? onOpenArtifact;

  /// Sends the trimmed follow-up text; the field is cleared when it completes.
  final Future<void> Function(String prompt)? onFollowUp;

  /// Called after the user confirms the action.
  final Future<void> Function()? onPause;
  final Future<void> Function()? onArchive;
  final Future<void> Function()? onUnarchive;

  @override
  State<AgentDetailPage> createState() => _AgentDetailPageState();
}

class _AgentDetailPageState extends State<AgentDetailPage> {
  final TextEditingController _followUp = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _followUp.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _agent {
    final Map<String, dynamic>? agent = widget.agent;
    if (agent == null || _text(agent['bcId']) != widget.bcId) {
      return null;
    }
    return agent;
  }

  bool get _canSend =>
      widget.onFollowUp != null &&
      !widget.busy &&
      !_sending &&
      _followUp.text.trim().isNotEmpty;

  Future<void> _send() async {
    final Future<void> Function(String prompt)? send = widget.onFollowUp;
    if (send == null || !_canSend) {
      return;
    }
    setState(() => _sending = true);
    try {
      await send(_followUp.text.trim());
      if (mounted) {
        _followUp.clear();
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _confirm(_AgentAction action) async {
    final String question = switch (action) {
      _AgentAction.pause => 'Pause this agent?',
      _AgentAction.archive => 'Archive this agent?',
      _AgentAction.unarchive => 'Restore this agent?',
    };
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Confirm agent action'),
        content: Text(question),
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
    if (confirmed != true || !mounted) {
      return;
    }
    final Future<void> Function()? run = switch (action) {
      _AgentAction.pause => widget.onPause,
      _AgentAction.archive => widget.onArchive,
      _AgentAction.unarchive => widget.onUnarchive,
    };
    await run?.call();
  }

  Future<void> _openArtifact(
    AgentArtifactOpener open,
    Map<String, dynamic> artifact,
  ) async {
    final String? body = await open(artifact);
    if (!mounted) {
      return;
    }
    if (body == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Artifact'),
        content: SingleChildScrollView(
          child: SelectableText(
            body.trim().isEmpty ? 'No bytes returned.' : body,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? error = widget.errorMessage;
    final Map<String, dynamic>? agent = _agent;
    final List<Widget> children = <Widget>[
      if (error != null && error.trim().isNotEmpty)
        Text(
          safeInboxError(error),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
        ),
      if (agent == null) ...<Widget>[
        Text('Loading this workspace…', style: theme.textTheme.bodyLarge),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            label: const Text('Retry'),
            onPressed: widget.onRefresh,
          ),
        ),
      ] else
        ..._details(theme, agent),
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

  List<Widget> _details(ThemeData theme, Map<String, dynamic> agent) {
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? secondary = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final TextStyle? note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final String name = _text(agent['name']);
    final String status = _text(agent['status']);
    final bool archived = status == 'ARCHIVED';
    final Future<void> Function()? archiveAction = archived
        ? widget.onUnarchive
        : widget.onArchive;
    final AgentArtifactOpener? open = widget.onOpenArtifact;
    final List<({Map<String, dynamic> artifact, String title})> titled =
        <({Map<String, dynamic> artifact, String title})>[
          for (final Map<String, dynamic> artifact in widget.artifacts)
            if (artifactTitle(artifact) case final String title)
              (artifact: artifact, title: title),
        ];
    return <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name.trim().isEmpty ? 'Agent' : name,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          AgentStatus(status: status),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ActionChip(
                label: const Text('Refresh'),
                onPressed: widget.onRefresh,
              ),
              ActionChip(
                label: const Text('Workspace ↗'),
                onPressed: widget.onOpenWorkspace,
              ),
              ActionChip(
                label: const Text('Artifacts'),
                onPressed: widget.onToggleArtifacts,
              ),
              if (!unpausableStatuses.contains(status))
                ActionChip(
                  label: Text(
                    widget.pauseUnavailable ? 'Pause unavailable' : 'Pause',
                  ),
                  onPressed: widget.pauseUnavailable || widget.onPause == null
                      ? null
                      : () => _confirm(_AgentAction.pause),
                ),
              ActionChip(
                label: Text(archived ? 'Restore' : 'Archive'),
                onPressed: archiveAction == null
                    ? null
                    : () => _confirm(
                        archived ? _AgentAction.unarchive : _AgentAction.archive,
                      ),
              ),
            ],
          ),
          if (widget.pauseUnavailable) ...<Widget>[
            const SizedBox(height: 8),
            Text('This response cannot pause the agent.', style: note),
          ],
        ],
      ),
      if (widget.streamText.trim().isNotEmpty)
        _ConversationCard(text: widget.streamText),
      if (widget.showArtifacts && titled.isEmpty)
        Text('No artifacts returned.', style: secondary),
      if (widget.showArtifacts)
        for (final ({Map<String, dynamic> artifact, String title}) item
            in titled)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: open == null
                  ? null
                  : () => _openArtifact(open, item.artifact),
              child: Text(item.title),
            ),
          ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const ValueKey<String>('agent-follow-up'),
            controller: _followUp,
            onChanged: (String _) => setState(() {}),
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Follow up',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _canSend ? _send : null,
              child: const Text('Send follow-up'),
            ),
          ),
        ],
      ),
    ];
  }
}

/// The conversation so far in selectable monospace text.
class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.text});

  final String text;

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
            Text(
              'Conversation',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
