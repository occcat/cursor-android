/// App routes. Inbox and Settings read `webConnected` from
/// [webConnectedProvider], a local cookie read. With a stored cookie the
/// Inbox also shows agents from [inboxAgentsProvider]: the first page, and
/// later pages appended by Load more while the list reports more. Its
/// Include archived filter sets [inboxIncludeArchivedProvider], so the
/// server decides whether archived agents are listed, and its cards archive
/// or restore an agent after the user confirms. Search stays a local name
/// filter and Refresh is not wired yet. Every other input is still stub
/// data and no other route calls the network. The one platform call is the
/// Settings floating capsule button, which opens the overlay permission
/// screen or, once drawing over other apps is allowed, starts the overlay
/// service. Later rounds replace the stubs with live state.
library;

import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/providers/inbox_agents_providers.dart';
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
                preferences: const Preferences(),
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
            builder: (BuildContext context, WidgetRef ref, Widget? _) =>
                SettingsPage(
                  preferences: const Preferences(),
                  webConnected: watchWebConnected(ref),
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
                ),
          ),
        ),
      ),
      GoRoute(
        path: '/create',
        builder: (BuildContext context, GoRouterState state) =>
            const _Frame(title: 'New agent', child: CreateAgentPage()),
      ),
      GoRoute(
        path: '/agent/:bcId',
        builder: (BuildContext context, GoRouterState state) => _Frame(
          title: 'Agent',
          child: AgentDetailPage(bcId: state.pathParameters['bcId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/environment/:publicId',
        builder: (BuildContext context, GoRouterState state) => _Frame(
          title: 'Cloud environment',
          child: EnvironmentPage(
            publicId: state.pathParameters['publicId'] ?? '',
          ),
        ),
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
