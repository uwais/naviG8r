import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/sign_in_phone_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const logo = AssetImage('assets/brand/navig8r-logo.png');

  Future<void> showPage(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final phone = TextEditingController();
    addTearDown(phone.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      // The same new-account links the real sign-in shows, so the page is as long as it is live.
      home: SignInPhonePage(
        phone: phone,
        sending: false,
        onSend: () {},
        newAccountLinks: {
          'Register a shipper company': () {},
          'Join a shipper company': () {},
          'Register a carrier company': () {},
          'Join a carrier company': () {},
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the logo sits above the heading, left-aligned with it',
      (tester) async {
    await showPage(tester);

    expect(find.image(logo), findsOneWidget);
    // Fails the test if the file is not in the bundle or does not decode.
    await tester.runAsync(
        () => precacheImage(logo, tester.element(find.image(logo))));
    final logoBox = tester.getRect(find.image(logo));
    final headingBox = tester.getRect(find.text('Sign in with your phone'));
    expect(logoBox.bottom, lessThan(headingBox.top),
        reason: 'the logo comes first, above the heading');
    expect(logoBox.left, headingBox.left,
        reason: 'left-aligned to match the heading');
    expect(logoBox.height, 52);
  });

  testWidgets('screen readers hear NaviG8r once for the logo', (tester) async {
    final semantics = tester.ensureSemantics();
    await showPage(tester);

    expect(find.bySemanticsLabel('NaviG8r'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('on a 360 by 640 screen the phone field is still in view',
      (tester) async {
    await showPage(tester);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(TextField)).bottom, lessThan(640),
        reason: 'the logo must not push the phone field off the first screen');
  });

  testWidgets('at 200% text on 360 by 640 nothing overflows', (tester) async {
    await showPage(tester, textScale: 2);

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text, nothing overflows');
    expect(find.image(logo), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Send code'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Send code'), findsOneWidget,
        reason: 'the page scrolls to the button');
  });
}
