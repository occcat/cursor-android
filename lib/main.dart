import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Brand accent. Used as [ColorScheme.primary] for graphics only.
const Color accentColor = Color(0xFFF54E00);

/// Warm-neutral light background.
const Color lightBackground = Color(0xFFF7F7F4);

/// Warm-neutral dark background.
const Color darkBackground = Color(0xFF14120B);

void main() {
  runApp(const ProviderScope(child: CursorApp()));
}

/// Provides the app-wide [GoRouter].
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return const HomePage();
        },
      ),
    ],
  );
});

/// Builds the Material 3 theme for [brightness].
ThemeData buildTheme(Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  final Color background = isDark ? darkBackground : lightBackground;
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  ).copyWith(
    primary: accentColor,
    onPrimary: Colors.white,
    surface: background,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
  );
}

/// Root widget of the Flutter rewrite.
class CursorApp extends ConsumerWidget {
  const CursorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Cursor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Placeholder home page.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Cursor',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
