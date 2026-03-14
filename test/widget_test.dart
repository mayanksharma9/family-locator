import 'package:flutter_test/flutter_test.dart';

import 'package:family_locator/main.dart';

void main() {
  testWidgets('renders relay-based family locator shell', (WidgetTester tester) async {
    await tester.pumpWidget(const FamilyLocatorApp());

    expect(find.text('Family Locator'), findsOneWidget);
    expect(find.text('Relay URL'), findsOneWidget);
    expect(find.text('Family code'), findsOneWidget);
    expect(find.text('Connect & share'), findsOneWidget);
    expect(find.text('Visible, consent-based family sharing'), findsOneWidget);
    expect(find.byTooltip('Refresh my location'), findsOneWidget);
    expect(find.byTooltip('Recenter map'), findsOneWidget);
  });
}
