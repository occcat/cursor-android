/// App routes. Every page gets stub, disconnected data for now: nothing here
/// calls the network or reads storage. The one platform call is the Settings
/// floating capsule button, which opens the overlay permission screen or, once
/// drawing over other apps is allowed, starts the overlay service. Later rounds
/// replace the stubs with live state.
library;

import 'package:cursor_android/domain/preferences.dart';
import 'package:cursor_android/system/overlay_bridge.dart';
import 'package:cursor_android/ui/agent_detail_page.dart';
import 'package:cursor_android/ui/create_agent_page.dart';
import 'package:cursor_android/ui/environment_page.dart';
import 'package:cursor_android/ui/inbox_page.dart';
import 'package:cursor_android/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The router for the app, starting at [initialLocation].
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
          child: InboxPage(
            webConnected: false,
            preferences: const Preferences(),
            onCreate: () => context.push('/create'),
            onOpenAgent: (String bcId) => context.push('/agent/$bcId'),
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) => _Frame(
          title: 'Settings',
          child: SettingsPage(
            preferences: const Preferences(),
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
