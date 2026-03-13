import 'package:flutter_test/flutter_test.dart';

import 'package:family_locator/main.dart';

void main() {
  testWidgets('renders family locator shell', (WidgetTester tester) async {
    await tester.pumpWidget(const FamilyLocatorApp());

    expect(find.text('Family Locator'), findsOneWidget);
    expect(find.textContaining('consent'), findsOneWidget);
  });
}
