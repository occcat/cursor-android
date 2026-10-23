/// App routes. Inbox and Settings read `webConnected` from
/// [webConnectedProvider], a local cookie read, and their preferences from
/// [preferencesProvider], which Settings changes and stores on the device.
/// With a stored cookie the Inbox also shows agents from
/// [inboxAgentsProvider]: the first page, and later pages appended by Load
/// more while the list reports more. Its Include archived filter sets
/// [inboxIncludeArchivedProvider], so the server decides whether archived
/// agents are listed, and its cards archive or restore an agent after the user
/// confirms. Search stays a local name filter and Refresh is not wired yet.
/// With a stored cookie New agent starts the agent through
/// [watchCreateAgentSubmit], then replaces itself with the agent's route, or
/// shows a safe error in a snack bar and keeps the form; Agent loads its agent
/// from [agentDetailProvider] and runs Refresh, follow-up, Pause, Archive and
/// Restore through it; and Cloud environment loads its environment and runtime
/// values from [environmentDetailProvider] and runs Refresh, Save, add and
/// revoke through it. Every other input is still stub data and no other route
/// calls the network. The one platform call is the Settings floating capsule
/// button, which opens the overlay permission screen or, once drawing over
/// other apps is allowed, starts the overlay service. Later rounds replace the
/// stubs with live state.
library;

import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/providers/agent_detail_providers.dart';
import 'package:cursor_android/providers/create_agent_providers.dart';
import 'package:cursor_android/providers/environment_providers.dart';
import 'package:cursor_android/providers/inbox_agents_providers.dart';
import 'package:cursor_android/providers/preferences_providers.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:cursor_android/system/overlay_bridge.dart';
import 'package:cursor_android/ui/agent_detail_page.dart';
import 'package:cursor_android/ui/create_agent_page.dart';
import 'package:cursor_android/ui/environment_page.dart';
import 'package:cursor_android/ui/inbox_page.dart';
import 'package:cursor_android/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The router for the app, starting at [initialLocation].
///
/// Must be shown under a `ProviderScope`.
GoRouter createAppRouter({String initialLocation = '/'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => _Frame(
          title: 'Cursor',
          actions: <Widget>[
            TextButton(
              onPressed: () => context.push('/settings'),
              child: const Text('Settings'),
            ),
          ],
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              final InboxAgentsView inbox = watchInboxAgents(ref);
              InboxAgentsNotifier agents() =>
                  ref.read(inboxAgentsProvider.notifier);
              return InboxPage(
                webConnected: watchWebConnected(ref),
                preferences: watchPreferences(ref).preferences,
                loading: inbox.loading,
                errorMessage: inbox.errorMessage,
                agents: inbox.agents,
                hasMore: inbox.hasMore,
                includeArchived: inbox.includeArchived,
                archivingBcId: inbox.actionBcId,
                onCreate: () => context.push('/create'),
                onLoadMore: inbox.canLoadMore
                    ? () => agents().loadMore()
                    : null,
                onOpenAgent: (String bcId) => context.push('/agent/$bcId'),
                onIncludeArchivedChanged: (bool value) => ref
                    .read(inboxIncludeArchivedProvider.notifier)
                    .choose(value),
                onArchive: inbox.canArchive || inbox.actionBcId != null
                    ? (String bcId) => agents().archive(bcId)
                    : null,
                onRestore: inbox.canArchive || inbox.actionBcId != null
                    ? (String bcId) => agents().restore(bcId)
                    : null,
              );
            },
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) => _Frame(
          title: 'Settings',
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              final ({Preferences preferences, bool loaded}) stored =
                  watchPreferences(ref);
              return SettingsPage(
                preferences: stored.preferences,
                webConnected: watchWebConnected(ref),
                onPreferencesChanged: stored.loaded
                    ? (Preferences next) =>
                          ref.read(preferencesProvider.notifier).save(next)
                    : null,
                onOpenEnvironment: (String publicId) =>
                    context.push('/environment/$publicId'),
                onOpenFloatingCapsuleHelp: () async {
                  const OverlayBridge bridge = OverlayBridge();
                  if (!await bridge.canDrawOverlays()) {
                    await bridge.openOverlaySettings();
                  } else {
                    await bridge.startOverlay();
                  }
                },
              );
            },
          ),
        ),
      ),
      GoRoute(
        path: '/create',
        builder: (BuildContext context, GoRouterState state) => _Frame(
          title: 'New agent',
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                CreateAgentPage(
                  onSubmit: watchCreateAgentSubmit(
                    ref,
                    onStarted: (String bcId) {
                      if (context.mounted) {
                        context.pushReplacement('/agent/$bcId');
                      }
                    },
                    onFailed: (String message) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(message)));
                      }
                    },
                  ),
                ),
          ),
        ),
      ),
      GoRoute(
        path: '/agent/:bcId',
        builder: (BuildContext context, GoRouterState state) {
          final String bcId = state.pathParameters['bcId'] ?? '';
          return _Frame(
            title: 'Agent',
            child: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                final AgentDetailView view = watchAgentDetail(ref, bcId);
                AgentDetailNotifier notifier() =>
                    ref.read(agentDetailProvider(bcId).notifier);
                final bool live = view.connected;
                return AgentDetailPage(
                  bcId: bcId,
                  agent: view.agent,
                  busy: view.busy,
                  pauseUnavailable: view.pauseUnavailable,
                  errorMessage: view.errorMessage,
                  onRefresh: live ? () => notifier().refresh() : null,
                  onFollowUp: live
                      ? (String prompt) => notifier().followUp(prompt)
                      : null,
                  onPause: live ? () => notifier().pause() : null,
                  onArchive: live ? () => notifier().archive() : null,
                  onUnarchive: live ? () => notifier().unarchive() : null,
                );
              },
            ),
          );
        },
      ),
      GoRoute(
        path: '/environment/:publicId',
        builder: (BuildContext context, GoRouterState state) {
          final String publicId = state.pathParameters['publicId'] ?? '';
          return _Frame(
            title: 'Cloud environment',
            child: Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                final EnvironmentDetailView view = watchEnvironmentDetail(
                  ref,
                  publicId,
                );
                EnvironmentDetailNotifier notifier() =>
                    ref.read(environmentDetailProvider(publicId).notifier);
                final bool live = view.connected;
                return EnvironmentPage(
                  publicId: publicId,
                  busy: view.busy,
                  loaded: view.loaded,
                  name: view.name,
                  environmentJson: view.environmentJson,
                  secrets: view.secrets,
                  errorMessage: view.errorMessage,
                  onRefresh: live ? () => notifier().refresh() : null,
                  onSave: live
                      ? (String _, String json) => notifier().save(json)
                      : null,
                  onAddSecret: live
                      ? (String name, String value) =>
                            notifier().addSecret(name, value)
                      : null,
                  onRevokeSecret: live
                      ? (String name, String? id) =>
                            notifier().revokeSecret(name, id)
                      : null,
                );
              },
            ),
          );
        },
      ),
    ],
  );
}

/// A page under an app bar; pushed routes get the automatic back button.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    required this.child,
    this.actions = const <Widget>[],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(child: child),
    );
  }
}
