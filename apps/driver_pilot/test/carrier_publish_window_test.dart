// The departure window on Publish (ca-publish, PR 7 of the redesign): the two leaving days, which days can
// be chosen, and the window sent.
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/ui/nv_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/carrier_office_screens.dart';

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Publish (ca-publish)', () {
    group('the departure window', () {
      // 01:30 on 20 Apr in India while it is still 19 Apr in UTC, so "today" must be India's.
      setUp(() => currentTime = () => DateTime.utc(2026, 4, 19, 20));
      tearDown(() => currentTime = DateTime.now);

      Widget publish() => DriverPublishTripScreen(
          findPlace: (place) async =>
              GeocodeOutcome.ok(const LatLng(13.07, 77.8), '$place, Karnataka'));

      Finder picker(String label) => find.descendant(
          of: find.ancestor(
              of: find.text(label), matching: find.byType(MergeSemantics)),
          matching: find.byType(OutlinedButton));

      DatePickerDialog openDialog(WidgetTester tester) =>
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));

      /// Opens the picker under [label] and taps [day] of the month it shows, then OK.
      Future<void> chooseDay(WidgetTester tester, String label, String day) async {
        await tester.tap(picker(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(day));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      Future<void> fillAllButDays(WidgetTester tester) async {
        for (final (index, place) in [(0, 'Hoskote'), (1, 'Kolar')]) {
          await tester.enterText(find.byType(TextField).at(index), place);
          await tester.tap(find.byTooltip('Search for place').at(index));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
        await tester.enterText(find.byType(TextField).last, '500');
        await tester.pumpAndSettle();
      }

      testWidgets('reads "Leaves between [day] and [day]", with no day chosen',
          (tester) async {
        signInWith(Server(allowed: ownerAllowed));
        final semantics = tester.ensureSemantics();
        await mount(tester, publish(), size: const Size(800, 3000));
        expect(find.text('Arrives by'), findsNothing,
            reason: 'Rishabh: a trip has no arrival date');
        final first = tester.getTopLeft(find.text('Leaves between'));
        final last = tester.getTopLeft(find.text('and'));
        expect(first.dy, last.dy, reason: 'the two labels share a line');
        expect(first.dx, lessThan(last.dx), reason: 'read left to right');
        expect(
            [picker('Leaves between'), picker('and')].map((button) =>
                tester.widget<Text>(find.descendant(
                    of: button, matching: find.byType(Text))).data),
            ['Choose a date', 'Choose a date'],
            reason: 'no day is chosen for the carrier');
        expect(find.bySemanticsLabel(RegExp('First day the truck can leave')),
            findsOneWidget,
            reason: 'a screen reader hears each picker on its own');
        expect(find.bySemanticsLabel(RegExp('Last day the truck can leave')),
            findsOneWidget);
        semantics.dispose();
      });

      testWidgets(
          'the first day cannot be before India\'s today, and the last cannot be before the first',
          (tester) async {
        signInWith(Server(allowed: ownerAllowed));
        await mount(tester, publish(), size: const Size(800, 3000));
        await tester.tap(picker('Leaves between'));
        await tester.pumpAndSettle();
        expect(openDialog(tester).firstDate, DateTime(2026, 4, 20),
            reason: 'days before today in India are refused');
        await tester.tap(find.text('24'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await tester.tap(picker('and'));
        await tester.pumpAndSettle();
        expect(openDialog(tester).firstDate, DateTime(2026, 4, 24),
            reason: 'the last day cannot be before the first');
        await tester.tap(find.text('23'));
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.text('24 Apr 2026'), findsNWidgets(2),
            reason: 'the 23rd could not be chosen; the last day may equal the first');
      });

      testWidgets('Publish asks for the first day, then the last, and sends nothing',
          (tester) async {
        final server = signInWith(Server(allowed: ownerAllowed));
        await mount(tester, publish(), size: const Size(800, 3000));
        await fillAllButDays(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
        await tester.pumpAndSettle();
        expect(find.text('Choose the first day the truck can leave.'),
            findsOneWidget);

        await chooseDay(tester, 'Leaves between', '24');
        await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
        await tester.pumpAndSettle();
        expect(find.text('Choose the last day the truck can leave.'),
            findsOneWidget);
        expect(find.text('Choose the first day the truck can leave.'),
            findsNothing);
        expect(server.sent, isEmpty);
      });

      for (final (lastDay, windowEnd) in [
        ('25', '2026-04-25T23:59:59+05:30'),
        ('24', '2026-04-24T23:59:59+05:30'),
      ]) {
        testWidgets(
            'leaving between the 24th and the ${lastDay}th sends that window as windowStart and windowEnd',
            (tester) async {
          final server = signInWith(Server(allowed: ownerAllowed));
          await mount(tester, publish(), size: const Size(800, 3000));
          await fillAllButDays(tester);
          await chooseDay(tester, 'Leaves between', '24');
          await chooseDay(tester, 'and', lastDay);
          await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
          await tester.pumpAndSettle();
          final published = server.sent.single.data as Map<String, dynamic>;
          expect(published['windowStart'], '2026-04-24T00:00:00+05:30',
              reason: 'the start of the first day the truck can leave, in India');
          expect(published['windowEnd'], windowEnd,
              reason: 'the end of the last day the truck can leave, in India');
        });
      }

      testWidgets('going to another tab and back keeps both leaving days',
          (tester) async {
        final server = signInWith(Server(allowed: ownerAllowed));
        final router =
            await mount(tester, publish(), size: const Size(800, 3000));
        await fillAllButDays(tester);
        await chooseDay(tester, 'Leaves between', '24');
        await chooseDay(tester, 'and', '26');
        router.go('/driver/loads');
        await tester.pumpAndSettle();
        router.go('/screen');
        await tester.pumpAndSettle();
        expect(
            find.descendant(
                of: picker('Leaves between'), matching: find.text('24 Apr 2026')),
            findsOneWidget);
        expect(find.descendant(of: picker('and'), matching: find.text('26 Apr 2026')),
            findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
        await tester.pumpAndSettle();
        final published = server.sent.single.data as Map<String, dynamic>;
        expect([published['windowStart'], published['windowEnd']],
            ['2026-04-24T00:00:00+05:30', '2026-04-26T23:59:59+05:30']);
      });

      testWidgets('filled in, with the route map, Publish fits 360 dp at 200% text',
          (tester) async {
        signInWith(Server(allowed: ownerAllowed));
        final router =
            await mount(tester, publish(), size: const Size(800, 3000));
        await fillAllButDays(tester);
        await chooseDay(tester, 'Leaves between', '24');
        await chooseDay(tester, 'and', '26');
        router.go('/driver/loads');
        await tester.pumpAndSettle();
        // The kept draft fills the form again at the large text size.
        await mount(tester, publish(), textScale: 2);
        expect(tester.takeException(), isNull,
            reason: 'brief 7: 200% text, Publish filled in');
        final form = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(find.byType(NvMap), 200,
            scrollable: form);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('24 Apr 2026'), 200,
            scrollable: form);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
            find.text('You choose the truck when you accept the first booking.'),
            200,
            scrollable: form);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
