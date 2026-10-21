import 'package:cursor_android/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Cursor placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CursorApp()));
    await tester.pumpAndSettle();

    expect(find.text('Cursor'), findsOneWidget);
  });
}
