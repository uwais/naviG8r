// Truck sizes on the carrier screens are words, never SMALL, MEDIUM or LARGE, and are never chosen for
// the office (PR 7 of the redesign).
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/carrier_office_screens.dart';

/// Every word on screen, sheets and snackbars included.
String screenWords(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

final sizeCodes = RegExp(r'\b(SMALL|MEDIUM|LARGE)\b');

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Truck sizes are words, never SMALL, MEDIUM or LARGE', () {
    Future<void> expectNoSizeCodes(WidgetTester tester, String where) async {
      final words = screenWords(tester);
      expect(sizeCodes.hasMatch(words), isFalse, reason: '$where: $words');
    }

    testWidgets(
        'on Publish, Profile, the truck sheet, fleet invite and sign-up',
        (tester) async {
      signInWith(Server(allowed: ownerAllowed));
      await mount(
          tester, const DriverPublishTripScreen(key: ValueKey('publish')));
      await expectNoSizeCodes(tester, 'Publish');
      await mount(tester, const DriverProfileScreen(key: ValueKey('profile')),
          size: const Size(800, 3000));
      await expectNoSizeCodes(tester, 'Profile');
      await tester.tap(find.text('KA01AB1234'));
      await tester.pumpAndSettle();
      await expectNoSizeCodes(tester, 'Truck sheet');
      await mount(
          tester, const DriverFleetInviteScreen(key: ValueKey('invite')),
          size: const Size(800, 2000));
      await expectNoSizeCodes(tester, 'Fleet invite');
      await mount(tester, const DriverRegisterScreen(key: ValueKey('register')),
          size: const Size(800, 2000));
      await expectNoSizeCodes(tester, 'Sign-up');
    });

    testWidgets('inviting a driver asks for a size instead of sending MEDIUM',
        (tester) async {
      final server = signInWith(Server(allowed: ownerAllowed));
      await mount(tester, const DriverFleetInviteScreen(),
          size: const Size(800, 2000));
      expect(
          tester
              .widgetList<ChoiceChip>(find.byType(ChoiceChip))
              .where((chip) => chip.selected),
          isEmpty,
          reason: 'nothing preselected, the role included');
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Driver or Dispatcher.'), findsOneWidget,
          reason: 'decisions.md guardrail 6: the role is chosen, not assumed');
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(
                  find.widgetWithText(TextField, 'Truck capacity (kg)'))
              .controller
              ?.text,
          isEmpty,
          reason: 'decisions.md guardrail 6: no capacity filled in for them');
      await tester.tap(find.text('Invite driver'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a truck size.'), findsOneWidget);
      await tester.tap(find.text('Medium'));
      await tester.tap(find.text('Invite driver'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a truck capacity greater than 0 kg.'), findsOneWidget,
          reason: 'an empty capacity is asked for, not sent as 0');
      expect(server.sent, isEmpty);
    });
  });
}
