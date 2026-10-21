/// Settings page, ported from Kotlin 0.1.5 `SettingsScreen` in
/// `CursorApp.kt`. Preferences and actions are injected by the caller; the
/// page persists nothing and starts no platform services.
library;

import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/ui/create_agent_page.dart'
    show CreateAgentOption;
import 'package:flutter/material.dart';

/// Foreground refresh choices, in seconds.
const List<int> refreshIntervals = <int>[30, 60, 120, 300];

/// Connections, usage display, system surfaces, widgets, language and cloud
/// environments.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.preferences,
    this.webConnected = false,
    this.busy = false,
    this.environments = const <CreateAgentOption>[],
    this.onConnectWeb,
    this.onDisconnect,
    this.onPreferencesChanged,
    this.onLoadEnvironments,
    this.onOpenEnvironment,
    this.onOpenFloatingCapsuleHelp,
    this.onOpenWidgetHelp,
  });

  /// Current preferences; the page never changes them itself.
  final Preferences preferences;

  /// Whether a cursor.com web session is connected.
  final bool webConnected;

  /// Whether an action is running; disables `Load environments`.
  final bool busy;

  /// Loaded cloud environments: `publicId` and display name.
  final List<CreateAgentOption> environments;

  /// Opens the web sign-in.
  final VoidCallback? onConnectWeb;

  /// Signs out and clears local data, after the user confirms.
  final VoidCallback? onDisconnect;

  /// Receives the full copy after each toggle or chip; switches and chips
  /// are disabled when this is null.
  final ValueChanged<Preferences>? onPreferencesChanged;

  final VoidCallback? onLoadEnvironments;

  /// Called with an environment's `publicId`.
  final ValueChanged<String>? onOpenEnvironment;

  /// Starts or explains the floating capsule; hidden when null.
  final VoidCallback? onOpenFloatingCapsuleHelp;

  /// Adds or explains home screen widgets; hidden when null.
  final VoidCallback? onOpenWidgetHelp;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _confirmDisconnect() async {
    final VoidCallback? disconnect = widget.onDisconnect;
    if (disconnect == null) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Disconnect this device?'),
        content: const Text(
          'Credentials, cached agents, live output and usage will be cleared.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      disconnect();
    }
  }

  Widget _switch(
    String label,
    bool value,
    Preferences Function(bool value) next,
  ) {
    final ValueChanged<Preferences>? changed = widget.onPreferencesChanged;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: changed == null
          ? null
          : (bool checked) => changed(next(checked)),
    );
  }

  Widget _choice(
    String label, {
    required bool selected,
    required Preferences next,
  }) {
    final ValueChanged<Preferences>? changed = widget.onPreferencesChanged;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: changed == null ? null : (bool _) => changed(next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final TextStyle? secondary = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final Preferences preferences = widget.preferences;
    final VoidCallback? capsule = widget.onOpenFloatingCapsuleHelp;
    final VoidCallback? widgets = widget.onOpenWidgetHelp;
    final ValueChanged<String>? openEnvironment = widget.onOpenEnvironment;
    final List<Widget> children = <Widget>[
      Text('Make it yours.', style: theme.textTheme.headlineMedium),
      const _Section('CONNECTIONS'),
      Text('Web session', style: theme.textTheme.titleMedium),
      Text(
        widget.webConnected
            ? 'Signed in with the cursor.com session stored on this device.'
            : 'Sign in inside the app. The session cookie stays encrypted on '
                  'this device.',
        style: secondary,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonal(
          onPressed: widget.onConnectWeb,
          child: Text(
            widget.webConnected
                ? 'Reconnect web session'
                : 'Connect web session',
          ),
        ),
      ),
      if (widget.webConnected)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.onDisconnect == null ? null : _confirmDisconnect,
            child: const Text('Disconnect & clear local data'),
          ),
        ),
      const _Section('CURSOR USAGE'),
      _switch(
        'Cursor Model',
        preferences.cursor,
        (bool value) => preferences.copyWith(cursor: value),
      ),
      _switch(
        'Other Model',
        preferences.other,
        (bool value) => preferences.copyWith(other: value),
      ),
      _switch(
        'Show remaining allowance',
        preferences.remaining,
        (bool value) => preferences.copyWith(remaining: value),
      ),
      _switch(
        'Billing pace',
        preferences.pace,
        (bool value) => preferences.copyWith(pace: value),
      ),
      _switch(
        'Pause automatic refresh',
        preferences.paused,
        (bool value) => preferences.copyWith(paused: value),
      ),
      const Text('Foreground refresh'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final int seconds in refreshIntervals)
            _choice(
              '${seconds}s',
              selected: preferences.intervalSeconds == seconds,
              next: preferences.copyWith(intervalSeconds: seconds),
            ),
        ],
      ),
      const _Section('SYSTEM SURFACES'),
      _switch(
        'Usage notification',
        preferences.notifications,
        (bool value) => preferences.copyWith(notifications: value),
      ),
      Text(
        'The status bar shows a monochrome icon. Values appear in the '
        'notification drawer; lock-screen details stay private.',
        style: secondary,
      ),
      if (capsule != null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed:
                widget.webConnected && (preferences.cursor || preferences.other)
                ? capsule
                : null,
            child: const Text('Start floating capsule'),
          ),
        ),
      Text(
        capsule == null
            ? 'The floating capsule needs overlay permission. It arrives in a '
                  'later update.'
            : 'Drag to position. Tap to open the app. The capsule displays '
                  'cached snapshots; Android schedules background refresh. '
                  'Starting requires overlay permission.',
        style: secondary,
      ),
      const _Section('HOME SCREEN WIDGETS'),
      Text(
        'Add Usage, Recent Agents or Quick Actions, then resize on your home '
        'screen. Cached snapshots refresh about every 15 minutes when Android '
        'permits.',
        style: secondary,
      ),
      _switch(
        'Show agent titles in widgets',
        preferences.widgetTitles,
        (bool value) => preferences.copyWith(widgetTitles: value),
      ),
      if (widgets != null)
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: widgets,
            child: const Text('Add widgets'),
          ),
        ),
      const _Section('LANGUAGE'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _choice(
            'English',
            selected: preferences.language == 'en',
            next: preferences.copyWith(language: 'en'),
          ),
          _choice(
            '简体中文',
            selected: preferences.language == 'zh-CN',
            next: preferences.copyWith(language: 'zh-CN'),
          ),
        ],
      ),
      if (widget.webConnected) ...<Widget>[
        const _Section('CLOUD ENVIRONMENTS'),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            onPressed: widget.busy ? null : widget.onLoadEnvironments,
            child: const Text('Load environments'),
          ),
        ),
        for (final CreateAgentOption environment in widget.environments)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: openEnvironment == null
                  ? null
                  : () => openEnvironment(environment.id),
              child: Text(environment.label),
            ),
          ),
      ],
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
