// Home, Book a trip and Book at the screen sizes the redesign names: the desktop width (PR 9) and
// 200% text on a 360 x 800 phone (PR 10).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/customer_layout.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:driver_pilot/ui/nv_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';
import 'support/shipper_screen_checks.dart';

void main() {
  desktopTests();
  doubleTextTests();
}

void desktopTests() {
  group('Desktop width (PR 9)', () {
    testWidgets(
        'at 1280 x 900 the price card and Pay are on screen together, beside the fields',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await showPricedBook(tester, width: 1280, height: 900);
      const screen = Rect.fromLTWH(0, 0, 1280, 900);
      bool onScreen(Finder finder) {
        final shown = tester.getRect(finder);
        return screen.contains(shown.topLeft) &&
            screen.contains(shown.bottomRight);
      }

      final price = find.text('₹2,640');
      final pay = find.text('Book and pay ₹2,640');
      expect(onScreen(price) && onScreen(pay), isTrue,
          reason: 'PR 9: the price card and Pay are on screen together');
      final fields = tester.getRect(field('Weight'));
      expect(tester.getRect(price).left, greaterThan(fields.right),
          reason: 'wb-book: the price card sits in the side column');
      expect(tester.getRect(pay).left, greaterThan(fields.right),
          reason: 'wb-book: Pay sits with the price, not in a bottom bar');
      expect(tester.getRect(find.text(contactAbovePay)).bottom,
          lessThanOrEqualTo(tester.getRect(pay).top),
          reason:
              'owner decision: the no-cancel line stays directly above Pay');
      expect(find.byType(NvActionBar), findsNothing,
          reason: 'desktop: no bottom action bar');
      expect(find.byType(NavigationBar), findsNothing,
          reason: 'PR 9: the top bar replaces the bottom tabs');

      final topBar = find.byType(CustomerTopNavigation);
      for (final words in ['NaviG8r', 'Home', 'Book a trip', 'Shipments']) {
        expect(find.descendant(of: topBar, matching: find.text(words)),
            findsOneWidget,
            reason: 'PR 9: the top bar shows "$words"');
      }
      expect(
          find.bySemanticsLabel(
              'Sharma Textiles, Priya Raman, Shipper. Switch company or sign out'),
          findsOneWidget,
          reason: 'PR 9: the account button is in the top bar');
      final back = find.descendant(
          of: find.byType(CustomerPageFrame),
          matching: find.text('Book a trip'));
      expect(back, findsOneWidget,
          reason:
              'wb-book: Back to the lanes sits in the page, above the title');
      expect(tester.getRect(back).bottom,
          lessThanOrEqualTo(tester.getRect(find.text('Book this trip')).top));
      semantics.dispose();
    });

    testWidgets(
        'content is at most 1200 wide and centred; the top links open tabs',
        (tester) async {
      final server =
          await showShipperApp(tester, '/customer', width: 1600, height: 900);
      server.answer('/shipments', {'shipments': []});
      await tester.pumpAndSettle();
      final content = tester.getRect(
          find.widgetWithText(FilledButton, 'Book a trip for new goods'));
      expect(content.width, lessThanOrEqualTo(1200),
          reason: 'PR 9: content max width 1200');
      expect(content.center.dx, closeTo(800, 1),
          reason: 'the content column is centred');

      await tester.tap(find.descendant(
          of: find.byType(CustomerTopNavigation),
          matching: find.text('Book a trip')));
      await tester.pumpAndSettle();
      expect(find.text('Pick a trip going your way.'), findsOneWidget,
          reason: 'the top bar link opens Book a trip');
    });

    testWidgets(
        'at 1280 lanes are a card grid, and Match sits beside its results',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips',
          width: 1280, height: 900);
      server.answer('/anchor-trips', {
        'trips': [
          lane(),
          lane(
              id: 'lane-2',
              from: 'Hosur',
              to: 'Kanchipuram',
              carrier: 'KTC Freight'),
        ]
      });
      await tester.pumpAndSettle();
      final first = tester.getRect(find.text('Bengaluru to Chennai'));
      final second = tester.getRect(find.text('Hosur to Kanchipuram'));
      expect(second.top, first.top,
          reason: 'PR 9: lanes become a card grid, side by side');
      expect(second.left, greaterThan(first.right));

      server.answer('/v1/customer/eligible-anchor-trips', {
        'trips': [
          {
            'trip': lane(),
            'eligibility': {'eligible': true}
          },
        ]
      });
      await tester.tap(find.text('Search by route'));
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      // The pickup map pushes the rest of the search column below 900.
      await scrollTo(tester, placeField('Drop'));
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await scrollTo(tester, field('Weight'));
      await tester.enterText(field('Weight'), '80');
      await scrollTo(tester, find.text('Find trips'));
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      final result = tester.getRect(find
          .text('1 trip with capacity for 80 kg, closest to your route first.'));
      expect(
          result.left, greaterThan(tester.getRect(find.text('Change')).right),
          reason: 'wb-lanes: the search sits beside its results');
    });

    testWidgets('at 360 x 800 the layout is the phone layout', (tester) async {
      await showPricedBook(tester, height: 800);
      expect(find.byType(CustomerTopNavigation), findsNothing,
          reason: 'PR 9: below 1024 there is no top bar');
      expect(
          find.ancestor(
              of: find.text('Book and pay ₹2,640'),
              matching: find.byType(NvActionBar)),
          findsOneWidget,
          reason: 'phone: Pay stays in the bottom action bar');
      await scrollTo(tester, find.text('₹2,640'));
      expect(
          find.ancestor(
              of: find.text('₹2,640'), matching: find.byType(ListView)),
          findsOneWidget,
          reason: 'phone: the price card is in the one column');
      expect(
          find.descendant(
              of: find.byType(NvHeader), matching: find.text('Book a trip')),
          findsOneWidget,
          reason: 'phone: Back is in the header');

      await tester.pumpWidget(const SizedBox());
      final server = await showShipperApp(tester, '/customer', height: 800);
      server.answer('/shipments', {'shipments': []});
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget,
          reason: 'phone: the tabs stay at the bottom');
    });
  });
}

void doubleTextTests() {
  group('200% text at 360 x 800 (PR 10)', () {
    testWidgets('Home, Browse, the Match form, its results and its empty state',
        (tester) async {
      useDoubleTextSize(tester);
      final server = await showShipperApp(tester, '/customer', height: 800);
      server.answer('/shipments', {
        'shipments': [
          {
            'id': 'needs-bill',
            'status': 'BOOKED',
            'carrierDisplayName': 'Ravi Roadways',
            'pickupAddress': 'Bommasandra, Bengaluru',
            'dropAddress': 'Guindy, Chennai',
            'assignedTruckNumber': 'KA01AB1234',
          },
          {'id': 'b', 'status': 'PENDING_CARRIER_ACCEPT'},
        ]
      });
      server.answer('/anchor-trips', {
        'trips': [
          lane(),
          lane(id: 'lane-2', to: 'Hyderabad', reservedKg: 1000, status: 'FULL')
        ]
      });
      server.answer(
          '/v1/notifications/shipments', {'shipments': [], 'unreadCount': 3});
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Home');

      await tester.tap(find.text('Book a trip').last);
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Browse');

      await tester.tap(find.text('Search by route'));
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'the Match form');

      server.answer('/v1/customer/eligible-anchor-trips', {
        'trips': [
          {
            'trip': lane(),
            'eligibility': {'eligible': true}
          },
        ]
      });
      await scrollTo(tester, placeField('Pickup'));
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await scrollTo(tester, placeField('Drop'));
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await expectNoOverflowToTheEnd(tester, 'the Match form with both maps');
      await scrollTo(tester, field('Weight'));
      await tester.enterText(field('Weight'), '80');
      await scrollTo(tester, find.text('Find trips'));
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Match results');

      server.answer('/v1/customer/eligible-anchor-trips', {'trips': []});
      await scrollTo(tester, find.text('Change'));
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Find trips'));
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Change weight'));
      await expectNoOverflowToTheEnd(tester, 'an empty match');
    });

    testWidgets(
        'Book with no places, with both maps while getting the price, with a price, and too heavy',
        (tester) async {
      useDoubleTextSize(tester);
      var server = await showShipperApp(
          tester, '/customer/book?anchorTripId=lane-1',
          height: 800);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Book before a price');

      await tester.pumpWidget(const SizedBox());
      final answer = Completer<ResponseBody>();
      server = await showShipperApp(tester, searchedBook,
          height: 800, initialExtra: searchedPlaces);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = (_) => answer.future;
      await pumpWhileWaiting(tester);
      await expectNoOverflowToTheEnd(tester, 'Book getting the price');

      answer.complete(jsonResponse({
        'quote': {'grossPaise': 264000}
      }));
      await tester.pumpAndSettle();
      await expectNoOverflowToTheEnd(tester, 'Book with a price');
      await expectNoOverflowToTheEnd(tester, 'the words beside Pay',
          list: find
              .descendant(
                  of: find.byType(NvActionBar),
                  matching: find.byType(Scrollable))
              .first);

      server.answers['/shipments/quote'] = priceByWeight;
      await scrollTo(tester, field('Weight'));
      await tester.enterText(field('Weight'), '150');
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Choose another trip'));
      await expectNoOverflowToTheEnd(tester, 'Book too heavy');
    });
  });
}
