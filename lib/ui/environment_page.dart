/// Cloud environment page, ported from Kotlin 0.1.5 `EnvironmentScreen` in
/// `CursorApp.kt`. Data and actions are injected by the caller; the page
/// never calls the network and never caches secret values.
library;

import 'dart:convert';

import 'package:cursor_android/ui/inbox_page.dart' show safeInboxError;
import 'package:flutter/material.dart';

/// Shown under `environment.json` when it is not a JSON object.
const String invalidEnvironmentJson = 'Enter a JSON object.';

String _text(Object? value) => value is String ? value : '';

bool _isJsonObject(String text) {
  try {
    return jsonDecode(text) is Map;
  } on FormatException {
    return false;
  }
}

/// One environment: its name and `environment.json`, plus runtime secret
/// names with add and revoke actions.
class EnvironmentPage extends StatefulWidget {
  const EnvironmentPage({
    super.key,
    required this.publicId,
    this.busy = false,
    this.loaded = false,
    this.name,
    this.environmentJson,
    this.secrets = const <Map<String, dynamic>>[],
    this.errorMessage,
    this.onRefresh,
    this.onSave,
    this.onAddSecret,
    this.onRevokeSecret,
  });

  /// The environment this page shows.
  final String publicId;

  /// Whether an action is running; disables every write action.
  final bool busy;

  /// Whether the caller has loaded [publicId]; the page shows the loading
  /// state until then.
  final bool loaded;

  /// Initial name. Adopted again when [loaded] turns true or [publicId]
  /// changes.
  final String? name;

  /// Initial `environment.json` text, adopted like [name].
  final String? environmentJson;

  /// Redacted secret metadata; only `name`, `type` and `id` are read.
  final List<Map<String, dynamic>> secrets;

  /// User-facing error text. Text that looks like it carries a cookie or
  /// secret is replaced by `genericInboxError`.
  final String? errorMessage;

  /// Reloads the environment and its secrets.
  final VoidCallback? onRefresh;

  /// Saves the trimmed name and the `environment.json` text after the user
  /// confirms. Only called when the text is a JSON object.
  final Future<void> Function(String name, String environmentJson)? onSave;

  /// Adds a secret with the trimmed name and the exact value.
  final Future<void> Function(String name, String value)? onAddSecret;

  /// Revokes a secret by name and, when present, its id, after the user
  /// confirms.
  final Future<void> Function(String name, String? id)? onRevokeSecret;

  @override
  State<EnvironmentPage> createState() => _EnvironmentPageState();
}

class _EnvironmentPageState extends State<EnvironmentPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _json = TextEditingController();
  final TextEditingController _secretName = TextEditingController();
  final TextEditingController _secretValue = TextEditingController();
  bool _invalidJson = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  @override
  void didUpdateWidget(EnvironmentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.publicId != widget.publicId) {
      _secretName.clear();
      _secretValue.clear();
      _adopt();
    } else if (!oldWidget.loaded && widget.loaded) {
      _adopt();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _json.dispose();
    _secretName.dispose();
    _secretValue.dispose();
    super.dispose();
  }

  void _adopt() {
    _name.text = widget.name ?? '';
    _json.text = widget.environmentJson ?? '';
    _invalidJson = false;
  }

  bool get _canAct => widget.loaded && !widget.busy && !_working;

  bool get _canSave =>
      _canAct && widget.onSave != null && _name.text.trim().isNotEmpty;

  bool get _canAdd =>
      _canAct &&
      widget.onAddSecret != null &&
      _secretName.text.trim().isNotEmpty &&
      _secretValue.text.trim().isNotEmpty;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    bool danger = false,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: danger
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(dialogContext).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _save() async {
    final Future<void> Function(String, String)? save = widget.onSave;
    if (save == null || !_canSave) {
      return;
    }
    final String text = _json.text;
    if (!_isJsonObject(text)) {
      setState(() => _invalidJson = true);
      return;
    }
    setState(() => _invalidJson = false);
    final bool confirmed = await _confirm(
      title: 'Replace configuration?',
      content: 'This changes the saved environment for future agents.',
    );
    if (!confirmed || !mounted) {
      return;
    }
    final String name = _name.text.trim();
    await _run(() => save(name, text));
  }

  Future<void> _revoke(String name, String id) async {
    final Future<void> Function(String, String?)? revoke =
        widget.onRevokeSecret;
    if (revoke == null || !_canAct) {
      return;
    }
    final bool confirmed = await _confirm(
      title: 'Revoke secret?',
      content: name,
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() => revoke(name, id.trim().isEmpty ? null : id));
  }

  Future<void> _addSecret() async {
    final Future<void> Function(String, String)? add = widget.onAddSecret;
    if (add == null || !_canAdd) {
      return;
    }
    final String name = _secretName.text.trim();
    final String value = _secretValue.text;
    await _run(() => add(name, value));
    if (mounted) {
      setState(() {
        _secretName.clear();
        _secretValue.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String? error = widget.errorMessage;
    final List<Widget> children = <Widget>[
      Text('Environment', style: theme.textTheme.headlineMedium),
      if (error != null && error.trim().isNotEmpty)
        Text(
          safeInboxError(error),
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
        ),
      if (!widget.loaded) ...<Widget>[
        Text('Loading this environment…', style: theme.textTheme.bodyLarge),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            label: const Text('Retry'),
            onPressed: widget.onRefresh,
          ),
        ),
      ] else
        ..._form(theme),
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _form(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? note = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final bool canRevoke = _canAct && widget.onRevokeSecret != null;
    final List<({String label, String name, String id})> rows =
        <({String label, String name, String id})>[
          for (final Map<String, dynamic> secret in widget.secrets)
            if (_text(secret['name']).trim().isNotEmpty)
              (
                label: _text(secret['type']).trim().isEmpty
                    ? _text(secret['name'])
                    : '${_text(secret['name'])} · ${_text(secret['type'])}',
                name: _text(secret['name']),
                id: _text(secret['id']),
              ),
        ];
    return <Widget>[
      TextField(
        key: const ValueKey<String>('environment-name'),
        controller: _name,
        onChanged: (String _) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Name',
          border: OutlineInputBorder(),
        ),
      ),
      TextField(
        key: const ValueKey<String>('environment-json'),
        controller: _json,
        onChanged: (String _) => setState(() => _invalidJson = false),
        minLines: 8,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        autocorrect: false,
        enableSuggestions: false,
        style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: 'environment.json',
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
          errorText: _invalidJson ? invalidEnvironmentJson : null,
        ),
      ),
      Text(
        'Saving replaces the full environment configuration. Repositories '
        'and owner stay unchanged.',
        style: note,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: _canSave ? _save : null,
          child: const Text('Save environment'),
        ),
      ),
      const _Section('RUNTIME SECRETS'),
      Text(
        'Values cannot be read back. New values are sent once and never '
        'cached.',
        style: note,
      ),
      for (final ({String label, String name, String id}) row in rows)
        Row(
          children: <Widget>[
            Expanded(child: Text(row.label)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: canRevoke ? () => _revoke(row.name, row.id) : null,
              child: const Text('Delete'),
            ),
          ],
        ),
      TextField(
        key: const ValueKey<String>('environment-secret-name'),
        controller: _secretName,
        onChanged: (String _) => setState(() {}),
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'New secret name',
          border: OutlineInputBorder(),
        ),
      ),
      TextField(
        key: const ValueKey<String>('environment-secret-value'),
        controller: _secretValue,
        onChanged: (String _) => setState(() {}),
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'Secret value',
          border: OutlineInputBorder(),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonal(
          onPressed: _canAdd ? _addSecret : null,
          child: const Text('Add secret'),
        ),
      ),
    ];
  }
}

/// A divider followed by a small section label.
class _Section extends StatelessWidget {
  const _Section(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
