import 'package:cursor_android/data/credentials.dart';
import 'package:cursor_android/main.dart';
import 'package:cursor_android/providers/session_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Cursor placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [credentialsProvider.overrideWithValue(MemoryCredentials())],
        child: const CursorApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cursor'), findsOneWidget);
  });
}
