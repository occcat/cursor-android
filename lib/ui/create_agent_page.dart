/// New agent page, ported from Kotlin 0.1.5 `CreateAgent` in `CursorApp.kt`.
/// Catalog data and the submit action are injected by the caller; the page
/// never calls the network itself.
library;

import 'package:flutter/material.dart';

/// One environment or model chip: the [id] sent to the server and the
/// [label] shown to the user.
typedef CreateAgentOption = ({String id, String label});

/// Starts an agent. [prompt] is trimmed, [repos] holds the non-empty
/// repository lines, and [model] and [environment] are empty for the account
/// default model and the default environment.
typedef CreateAgentSubmit =
    Future<void> Function({
      required String prompt,
      required List<String> repos,
      required String model,
      required String environment,
    });

/// Environment chips from `list-environments` rows: `publicId` is the id and
/// `name` the label, falling back to the id. Rows without an id are skipped.
List<CreateAgentOption> environmentOptions(
  Iterable<Map<String, dynamic>> rows,
) => _options(rows, 'publicId', 'name');

/// Model chips from `available-models` rows: `serverModelName` is the id and
/// `clientDisplayName` the label, falling back to the id. Rows without an id
/// are skipped.
List<CreateAgentOption> modelOptions(Iterable<Map<String, dynamic>> rows) =>
    _options(rows, 'serverModelName', 'clientDisplayName');

List<CreateAgentOption> _options(
  Iterable<Map<String, dynamic>> rows,
  String idKey,
  String labelKey,
) {
  final List<CreateAgentOption> options = <CreateAgentOption>[];
  for (final Map<String, dynamic> row in rows) {
    final String id = _nonBlank(row[idKey]);
    if (id.isEmpty) {
      continue;
    }
    final String label = _nonBlank(row[labelKey]);
    options.add((id: id, label: label.isEmpty ? id : label));
  }
  return options;
}

String _nonBlank(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : '';

/// The last path segment of [url], or the whole URL when that is empty.
String _repoLabel(String url) {
  final String last = url.substring(url.lastIndexOf('/') + 1);
  return last.isEmpty ? url : last;
}

/// The New agent form: task prompt, repositories or environment, model and
/// `Start agent →`. The caller supplies the catalog and starts the agent.
class CreateAgentPage extends StatefulWidget {
  const CreateAgentPage({
    super.key,
    this.busy = false,
    this.recentRepos = const <String>[],
    this.environments = const <CreateAgentOption>[],
    this.models = const <CreateAgentOption>[],
    this.onSubmit,
  });

  /// Whether an action is running; disables `Start agent →`.
  final bool busy;

  /// Recent repository `htmlUrl`s; the first 10 non-blank ones become chips.
  final List<String> recentRepos;

  /// Environment chips shown after `Default environment`.
  final List<CreateAgentOption> environments;

  /// Model chips shown after `Account default`.
  final List<CreateAgentOption> models;

  /// Starts the agent, for example with
  /// `CursorApi.startBackgroundComposerFromSnapshot`, and handles its errors
  /// and navigation. The button is disabled when this is null and while a
  /// call is in flight.
  final CreateAgentSubmit? onSubmit;

  @override
  State<CreateAgentPage> createState() => _CreateAgentPageState();
}

class _CreateAgentPageState extends State<CreateAgentPage> {
  final TextEditingController _prompt = TextEditingController();
  final TextEditingController _repos = TextEditingController();
  String _model = '';
  String _environment = '';
  bool _sending = false;

  @override
  void dispose() {
    _prompt.dispose();
    _repos.dispose();
    super.dispose();
  }

  bool get _canStart =>
      widget.onSubmit != null &&
      !widget.busy &&
      !_sending &&
      _prompt.text.trim().isNotEmpty;

  void _pickRepo(String url) {
    setState(() {
      _repos.text = url;
      _environment = '';
    });
  }

  void _pickEnvironment(String id) {
    setState(() {
      _environment = id;
      if (id.isNotEmpty) {
        _repos.clear();
      }
    });
  }

  Future<void> _start() async {
    final CreateAgentSubmit? submit = widget.onSubmit;
    if (submit == null || !_canStart) {
      return;
    }
    setState(() => _sending = true);
    try {
      await submit(
        prompt: _prompt.text.trim(),
        repos: <String>[
          for (final String line in _repos.text.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ],
        model: _model,
        environment: _environment,
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
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
    final List<String> repos = widget.recentRepos
        .where((String url) => url.trim().isNotEmpty)
        .take(10)
        .toList();
    final List<Widget> children = <Widget>[
      Text('What should we build?', style: theme.textTheme.headlineMedium),
      Text('Start a cloud agent with your own Cursor account.', style: secondary),
      TextField(
        key: const ValueKey<String>('create-agent-prompt'),
        controller: _prompt,
        onChanged: (String _) => setState(() {}),
        minLines: 5,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          labelText: 'Describe a task',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
      ),
      Text('Workspace', style: theme.textTheme.titleMedium),
      TextField(
        key: const ValueKey<String>('create-agent-repos'),
        controller: _repos,
        enabled: _environment.isEmpty,
        minLines: 1,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: const InputDecoration(
          labelText: 'Repository URLs · one per line',
          helperText: 'Leave empty to start without a repository.',
          border: OutlineInputBorder(),
        ),
      ),
      if (repos.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final String url in repos)
              ActionChip(
                label: Text(_repoLabel(url)),
                tooltip: url,
                onPressed: () => _pickRepo(url),
              ),
          ],
        ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          ChoiceChip(
            label: const Text('Default environment'),
            selected: _environment.isEmpty,
            onSelected: (bool _) => _pickEnvironment(''),
          ),
          for (final CreateAgentOption option in widget.environments)
            ChoiceChip(
              label: Text(option.label),
              selected: _environment == option.id,
              onSelected: (bool _) => _pickEnvironment(option.id),
            ),
        ],
      ),
      Text('Model', style: theme.textTheme.titleMedium),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          ChoiceChip(
            label: const Text('Account default'),
            selected: _model.isEmpty,
            onSelected: (bool _) => setState(() => _model = ''),
          ),
          for (final CreateAgentOption option in widget.models)
            ChoiceChip(
              label: Text(option.label),
              selected: _model == option.id,
              onSelected: (bool _) => setState(() => _model = option.id),
            ),
        ],
      ),
      FilledButton(
        onPressed: _canStart ? _start : null,
        child: const Text('Start agent →'),
      ),
      Text(
        'Runs may consume your Cursor allowance. Sending is never retried '
        'automatically.',
        style: note,
      ),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < children.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: 14),
            children[index],
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
