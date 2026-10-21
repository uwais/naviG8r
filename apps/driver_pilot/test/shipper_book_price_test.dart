// PR 4 of the redesign: Book's price, from the empty form to the price on Book and pay, the weight
// and lane refusals, and the fit at large text (sh-book-*). Names, places and amounts are the
// mockups' synthetic ones.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/shipper/shipper_routes.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';

void main() {
  group('Book', () {
    testWidgets('a Book link with no lane goes to Book a trip', (tester) async {
      final router = GoRouter(
          initialLocation: '/customer/book', routes: customerFlowRoutes());
      addTearDown(router.dispose);
      FlutterSecureStorage.setMockInitialValues({});
      api = Api('http://test');
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({}));
      CustomerSession.skipRefreshInTests = true;
      addTearDown(() => CustomerSession.skipRefreshInTests = false);
      CustomerSession.applyForTest(
          userFullName: 'Priya Raman',
          customerOrgId: 'org-sharma',
          customerOrgName: 'Sharma Textiles',
          customerRole: 'CUSTOMER_MEMBER');
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.path,
          '/customer/trips',
          reason:
              'decisions.md: Book is reached from a lane card, never with no lane');
    });

    testWidgets(
        'with no search the fields start empty, and Pay is disabled until weight, pickup and drop are in',
        (tester) async {
      final server =
          await showShipperApp(tester, '/customer/book?anchorTripId=lane-1');
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = priceByWeight;
      await tester.pumpAndSettle();
      expect(find.text('Book this trip'), findsOneWidget, reason: 'copy.md: title');
      expect(find.text('Check the price, then pay.'), findsOneWidget,
          reason: 'copy.md: sub');
      expect(find.text('Capacity remaining: 105 kg'), findsOneWidget,
          reason: 'room left from capacity 1000 and booked 895');
      expect(find.text('Ravi Roadways · Leaves 18 – 19 Oct'), findsOneWidget,
          reason: 'the dates are when the truck leaves, never an arrival');
      expect(find.text('Up to 105 kg on this trip.'), findsOneWidget,
          reason: 'copy.md: weight help');
      expect(tester.widget<TextField>(field('Weight')).controller!.text, '',
          reason: 'screens.md: with no search, Weight starts empty');
      for (final title in ['Pickup', 'Drop']) {
        expect(tester.widget<TextField>(placeField(title)).controller!.text,
            '',
            reason: 'screens.md: with no search, $title starts empty');
      }
      expect(find.text('Get price'), findsNothing,
          reason: 'Rishabh: no Get price step');

      Future<void> expectWaitingFor(String missing) async {
        await tester.pumpAndSettle();
        expect(bookButton(tester).onPressed, isNull,
            reason: 'Pay is disabled until there is a price');
        expect(bookButton(tester).label, 'Book and pay');
        expect(find.text(missing), findsOneWidget,
            reason: 'the line under Pay says what is missing');
        expect(server.countOf('/shipments/quote'), 0,
            reason: 'nothing to price yet');
      }

      await expectWaitingFor(
          'To see the price, enter the weight and search for the pickup and drop.');
      await tester.enterText(field('Weight'), '80');
      await expectWaitingFor('To see the price, search for the pickup and drop.');
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await expectWaitingFor('To see the price, search for the drop.');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      expect(server.countOf('/shipments/quote'), 1,
          reason: 'Rishabh: the price comes by itself once everything is in');
      expect(bookButton(tester).label, 'Book and pay ₹2,640');
      expect(bookButton(tester).onPressed, isNotNull);
    });

    testWidgets(
        'capacity remaining takes off the weight as it is typed, and the limit under Weight stays fixed',
        (tester) async {
      final server =
          await showShipperApp(tester, '/customer/book?anchorTripId=lane-1');
      server.answer('/anchor-trips/lane-1',
          {'trip': lane(capacityKg: 1000, reservedKg: 500)});
      server.answers['/shipments/quote'] = priceByWeight;
      await tester.pumpAndSettle();
      expect(find.text('Capacity remaining: 500 kg'), findsOneWidget,
          reason: 'an empty weight shows the full capacity');
      await tester.enterText(field('Weight'), '200');
      await tester.pump();
      expect(find.text('Capacity remaining: 300 kg'), findsOneWidget,
          reason: 'Rishabh: the amount left changes as the weight is typed');
      expect(find.text('Up to 500 kg on this trip.'), findsOneWidget,
          reason: 'the help under Weight is the fixed limit');
      await tester.enterText(field('Weight'), '600');
      await tester.pump();
      expect(find.text("100 kg more than the capacity remaining"), findsOneWidget,
          reason: 'over the limit says by how much, not "Capacity remaining: None"');
      expect(find.textContaining('Capacity remaining'), findsNothing);
      await tester.enterText(field('Weight'), '500');
      await tester.pump();
      expect(find.text('Capacity remaining: 0 kg'), findsOneWidget,
          reason: 'second review: an exact fit is 0 kg, not "None"');
      await tester.enterText(field('Weight'), '');
      await tester.pump();
      expect(find.text('Capacity remaining: 500 kg'), findsOneWidget,
          reason: 'clearing the weight shows the full capacity again');
    });

    testWidgets(
        'the price comes without a tap, with every part of it and the contact line beside Pay',
        (tester) async {
      final server = await showPricedBook(tester);
      expect(server.countOf('/shipments/quote'), 1,
          reason: 'Rishabh: no tap, the price is fetched on its own');
      expect(find.text('Get price'), findsNothing);
      expect(find.text('₹2,640'), findsOneWidget,
          reason: 'copy.md: the price, Indian grouping');
      expect(find.text(fullPriceLine), findsOneWidget,
          reason: 'decisions.md 6: full price on the same screen as Pay');
      expect(
          find.text('After you pay, Ravi Roadways accepts and names the truck.'),
          findsOneWidget,
          reason: 'moved from the confirm sheet onto the screen');
      expect(
          find.text(
              "Book and pay opens our payment partner's screen. There you choose how to pay."),
          findsOneWidget,
          reason: 'moved from the confirm sheet: what Pay does next');
      expect(find.text('If you change the weight, pickup or drop, the price changes.'),
          findsOneWidget,
          reason: 'copy.md: price note');
      expect(find.text(contactAbovePay), findsOneWidget,
          reason:
              'owner decision: no cancel in the app, the contact sits above Pay');
      expect(bookButton(tester).label, 'Book and pay ₹2,640',
          reason: 'Rishabh: the one button names the total');
      final quoted = server.sentTo('/shipments/quote').single;
      expect(quoted['weightKg'], 80);
      expect((quoted['pickup'] as Map)['lat'], 12.8,
          reason: 'the pickup pin from the search is priced');
    });

    testWidgets('while the price is coming the button says so',
        (tester) async {
      final answer = Completer<ResponseBody>();
      final server = await showShipperApp(tester, searchedBook,
          initialExtra: searchedPlaces);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = (_) => answer.future;
      await pumpWhileWaiting(tester);
      expect(find.text('Getting the price'), findsOneWidget,
          reason: 'Rishabh: say "Getting the price" while fetching');
      expect(find.textContaining('Book and pay ₹'), findsNothing);
      answer.complete(jsonResponse({
        'quote': {'grossPaise': 264000}
      }));
      await tester.pumpAndSettle();
      expect(bookButton(tester).label, 'Book and pay ₹2,640');
    });

    testWidgets('a new weight gets a new price, and Pay follows it',
        (tester) async {
      final server = await showPricedBook(tester);
      await tester.enterText(field('Weight'), '90');
      await tester.pumpAndSettle();
      expect(server.sentTo('/shipments/quote').last['weightKg'], 90);
      expect(find.text('₹2,640'), findsNothing,
          reason: 'brief A.2: shown price is the charged price');
      expect(bookButton(tester).label, 'Book and pay ₹2,970');
    });

    testWidgets('a late price answer for older inputs is ignored',
        (tester) async {
      final answers = <int, Completer<ResponseBody>>{};
      final server = await showShipperApp(tester, searchedBook,
          initialExtra: searchedPlaces);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = (request) => answers
          .putIfAbsent((request.data as Map)['weightKg'] as int,
              () => Completer<ResponseBody>())
          .future;
      await pumpWhileWaiting(tester);
      await tester.enterText(field('Weight'), '90');
      await pumpWhileWaiting(tester);
      answers[90]!.complete(jsonResponse({
        'quote': {'grossPaise': 297000}
      }));
      await tester.pumpAndSettle();
      answers[80]!.complete(jsonResponse({
        'quote': {'grossPaise': 264000}
      }));
      await tester.pumpAndSettle();
      expect(bookButton(tester).label, 'Book and pay ₹2,970',
          reason: 'the 80 kg answer came last but is for weight no longer entered');
      expect(find.text('₹2,640'), findsNothing);
    });

    testWidgets('a weight over the room left is refused before pricing',
        (tester) async {
      final server = await showPricedBook(tester);
      await tester.enterText(field('Weight'), '150');
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This trip does not have enough capacity for that weight. Enter less weight, or choose another trip.'),
          findsOneWidget,
          reason: 'sh-book-error: the too-heavy sentence under Weight');
      expect(server.sentTo('/shipments/quote').map((sent) => sent['weightKg']),
          isNot(contains(150)),
          reason: 'no price for a weight the lane cannot take');
      expect(bookButton(tester).onPressed, isNull,
          reason: 'no Pay without a price');
      expect(find.text('Enter less weight to see the price.'),
          findsOneWidget);
    });

    testWidgets('a server error never shows HTTP text, and Try again re-asks',
        (tester) async {
      final server = await showShipperApp(tester, searchedBook,
          initialExtra: searchedPlaces);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answer('/shipments/quote', {'error': 'boom', 'detail': 'x'}, 500);
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no "HTTP 500" in the app');
      expect(
          find.text(
              'Could not get a price. Check your connection, then try again.'),
          findsOneWidget,
          reason: 'a plain sentence instead');
      server.answers['/shipments/quote'] = priceByWeight;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(bookButton(tester).label, 'Book and pay ₹2,640');
    });

    testWidgets('a lane that is not open says so instead of offering a price',
        (tester) async {
      final server =
          await showShipperApp(tester, '/customer/book?anchorTripId=lane-1');
      server.answer('/anchor-trips/lane-1',
          {'trip': lane(reservedKg: 1000, status: 'FULL')});
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This trip is no longer taking bookings. Choose another trip.'),
          findsOneWidget,
          reason: 'a full lane cannot be booked');
      expect(find.textContaining('Book and pay'), findsNothing,
          reason: 'no price for a lane that takes no bookings');
    });

    testWidgets('Home, Browse and the Match form fit 360 dp at 200% text',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final server = await showShipperApp(tester, '/customer', height: 800);
      server.answer('/shipments', {
        'shipments': [
          {
            'id': 'a',
            'status': 'BOOKED',
            'carrierDisplayName': 'Ravi Roadways'
          },
          {'id': 'b', 'status': 'PENDING_CARRIER_ACCEPT'},
        ]
      });
      server.answer('/anchor-trips', {
        'trips': [lane()]
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: Home fits at 200% text');
      await tester.tap(find.text('Book a trip').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: Browse fits at 200% text');
      await tester.tap(find.text('Search by route'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: the Match form fits at 200% text');
    });

    testWidgets('the price state fits 360 dp at 200% text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await showPricedBook(tester, height: 800);
      expect(tester.takeException(), isNull,
          reason: 'decisions.md 8: 200% text at 360 dp');
      expect(find.textContaining('Book and pay ₹'), findsOneWidget,
          reason: 'Book and pay stays in the action bar at 200% text');
    });
  });
}
