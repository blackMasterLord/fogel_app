import 'package:flutter_test/flutter_test.dart';

import 'package:fogel_app/main.dart';

void main() {
  testWidgets('App renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const FogelApp());
    expect(find.text('FogelApp'), findsOneWidget);
  });
}
