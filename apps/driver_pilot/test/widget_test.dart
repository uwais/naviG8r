import 'package:flutter_test/flutter_test.dart';

import 'package:driver_pilot/main.dart';

void main() {
  testWidgets('App renders navigation tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const DriverPilotApp());

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
  });
}
