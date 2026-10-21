// PR 4 of the redesign: Book with the full price before paying (sh-book-*). Names, places and
// amounts are the mockups' synthetic ones.
// Over 500 lines on purpose: one screen's one test group. Its price, place and payment tests
// each walk the same form to the same button, so a split would cut one flow in two.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/shipper/book_a_lane.dart';
import 'package:driver_pilot/shipper/shipper_routes.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:driver_pilot/ui/nv_button.dart';
import 'package:driver_pilot/ui/nv_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';
import 'support/shipper_screen_checks.dart';

/// The one bottom button on Book.
NvButton bookButton(WidgetTester tester) => tester.widget<NvButton>(find
    .descendant(
        of: find.byType(NvActionBar), matching: find.byType(NvButton))
    .last);

const fullPriceLine = 'This is the full price. Nothing is added at payment.';

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
      expect(find.text("100 kg more than this trip's capacity"), findsOneWidget,
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
        'Book has the search-and-pin place box, with the pins the match search found',
        (tester) async {
      await showPricedBook(tester);
      expect(placeBox('Pickup'), findsOneWidget,
          reason: 'Rishabh: Book gets the place box Publish uses');
      expect(placeBox('Drop'), findsOneWidget);
      expect(pinIn(tester, 'Pickup').position, const LatLng(12.8, 77.7),
          reason: 'the pickup pin is where the match search put it');
      expect(pinIn(tester, 'Drop').position, const LatLng(13.0, 80.2),
          reason: 'the drop pin is where the match search put it');
      expect(pinIn(tester, 'Drop').draggable, isTrue);
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

    testWidgets('moving a pin gets a new price, and the pin is what is booked',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      });
      pinIn(tester, 'Drop').onDragEnd!(const LatLng(13.05, 80.25));
      await tester.pumpAndSettle();
      expect(server.countOf('/shipments/quote'), 2,
          reason: 'a moved pin is a new place to price');
      expect((server.sentTo('/shipments/quote').last['drop'] as Map)['lat'],
          13.05);
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      final booked = server.sentTo('/shipments/book').single;
      expect((booked['drop'] as Map)['lat'], 13.05,
          reason: 'Rishabh: the point sent is the pin\'s point');
      expect((booked['drop'] as Map)['lng'], 80.25);
    });

    testWidgets(
        'new words in a place box after a search keep its pin and price, and the new words are booked',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      });
      await tester.enterText(placeField('Pickup'), 'Gate 2, Plot 12, Hosur Road');
      await tester.pumpAndSettle();
      expect(pinIn(tester, 'Pickup').position, const LatLng(12.8, 77.7),
          reason: 'owner, 21 Oct 2026: typing never moves or drops the pin');
      expect(bookButton(tester).label, 'Book and pay ₹2,640',
          reason: 'the pin decides the price, so the price stays');
      expect(bookButton(tester).onPressed, isNotNull);
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      final booked = server.sentTo('/shipments/book').single;
      expect(booked['pickupAddress'], 'Gate 2, Plot 12, Hosur Road',
          reason: 'the typed words are the address for the driver');
      expect((booked['pickup'] as Map)['lat'], 12.8);
    });

    testWidgets(
        'Book shows both pins on one map, each with its Pin line, to check before paying',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/book?anchorTripId=lane-1',
          findPlace: (place) async => place.contains('Chennai')
              ? GeocodeOutcome.ok(const LatLng(13.0, 80.2),
                  'Guindy, Chennai, Tamil Nadu 600032, India', 'Chennai')
              : GeocodeOutcome.ok(const LatLng(12.8, 77.7),
                  'Bommasandra, Bengaluru, Karnataka 560099, India', 'Bengaluru'));
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = priceByWeight;
      await tester.pumpAndSettle();
      await tester.enterText(field('Weight'), '80');
      await searchPlace(tester, 'Pickup', 'Plot 12, Bommasandra');
      await searchPlace(tester, 'Drop', 'Gate 4, Guindy, Chennai');
      // Last in the list, under the price, so the shipper meets it just above Book and pay.
      await tester.scrollUntilVisible(
          find.text('Check the pins before you pay'), 300,
          scrollable: find
              .descendant(
                  of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      final bothPins = tester
          .widgetList<GoogleMap>(find.byType(GoogleMap))
          .where((map) => map.markers.length == 2)
          .single
          .markers
          .map((pin) => pin.position);
      expect(bothPins, containsAll(const [LatLng(12.8, 77.7), LatLng(13.0, 80.2)]),
          reason: 'owner, 21 Oct 2026: Book shows both pins on a map to check');
      for (final address in [
        'Pin: Bommasandra, Bengaluru, Karnataka 560099, India',
        'Pin: Guindy, Chennai, Tamil Nadu 600032, India',
      ]) {
        expect(find.text(address), findsNWidgets(2),
            reason: 'under its place box, and again in the check by the map');
      }
      expect(find.text('Plot 12, Bommasandra'), findsWidgets,
          reason: 'the check shows the typed words beside the pin they go with');
    });

    testWidgets('after a pin drag, typing its name keeps the dragged pin',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      });
      pinIn(tester, 'Drop').onDragEnd!(const LatLng(13.05, 80.25));
      await tester.pumpAndSettle();
      await tester.enterText(placeField('Drop'), 'Adyar, Chennai');
      await tester.pumpAndSettle();
      expect(bookButton(tester).label, 'Book and pay ₹2,640',
          reason: 'the dragged pin is the place; the name is the shipper\'s');
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      final booked = server.sentTo('/shipments/book').single;
      expect((booked['drop'] as Map)['lat'], 13.05);
      expect(booked['dropAddress'], 'Adyar, Chennai');
    });

    testWidgets('while the booking is sent, weight and both places cannot change',
        (tester) async {
      final answer = Completer<ResponseBody>();
      final server = await showPricedBook(tester);
      server.answers['/shipments/book'] = (_) => answer.future;
      await tester.tap(find.text('Book and pay ₹2,640'));
      await pumpWhileWaiting(tester);
      expect(tester.widget<TextField>(field('Weight')).readOnly, isTrue,
          reason: 'reviewer: the form could change under a booking being sent');
      for (final title in ['Pickup', 'Drop']) {
        expect(tester.widget<TextField>(placeField(title)).readOnly, isTrue,
            reason: '$title cannot be typed in');
        expect(
            tester
                .widget<IconButton>(find.descendant(
                    of: placeBox(title), matching: find.byType(IconButton)))
                .onPressed,
            isNull,
            reason: '$title cannot be searched');
        expect(pinIn(tester, title).draggable, isFalse,
            reason: 'the $title pin cannot be dragged');
      }

      answer.complete(jsonResponse({'error': 'internal_error'}, 500));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Weight')).readOnly, isFalse,
          reason: 'after a failed booking the form can be changed again');
      expect(pinIn(tester, 'Drop').draggable, isTrue);
    });

    testWidgets('a fast second tap on Book and pay sends one booking',
        (tester) async {
      final answer = Completer<ResponseBody>();
      final server = await showPricedBook(tester);
      server.answers['/shipments/book'] = (_) => answer.future;
      final pay = find.text('Book and pay ₹2,640');
      await tester.tap(pay);
      await tester.tap(pay);
      await pumpWhileWaiting(tester);
      expect(server.countOf('/shipments/book'), 1,
          reason: 'review: a double tap before the button redrew booked twice');
      answer.complete(jsonResponse({'error': 'internal_error'}, 500));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'after a pin drag, Book and pay waits until the pin is named, then books the typed words at the pin',
        (tester) async {
      final town = Completer<GeocodeOutcome>();
      final server = await showShipperApp(tester, searchedBook,
          namePin: (_) => town.future, initialExtra: searchedPlaces);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = priceByWeight;
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      });
      await tester.pumpAndSettle();
      pinIn(tester, 'Drop').onDragEnd!(const LatLng(13.05, 80.25));
      await tester.pumpAndSettle();
      expect(server.countOf('/shipments/quote'), 2,
          reason: 'the moved pin is priced at once');
      expect(bookButton(tester).onPressed, isNull,
          reason: 'review: the old town name could be booked with the new pin');
      expect(
          find.descendant(
              of: find.byType(NvActionBar),
              matching: find.text('Updating address from pin…')),
          findsOneWidget,
          reason: 'a disabled button says why');

      town.complete(GeocodeOutcome.ok(
          const LatLng(13.05, 80.25),
          '14, Lattice Bridge Rd, Adyar, Chennai, Tamil Nadu 600020, India',
          'Chennai'));
      await tester.pumpAndSettle();
      expect(bookButton(tester).onPressed, isNotNull);
      expect(
          find.descendant(
              of: placeBox('Drop'),
              matching: find.text(
                  'Pin: 14, Lattice Bridge Rd, Adyar, Chennai, Tamil Nadu 600020, India')),
          findsOneWidget,
          reason: 'the pin\'s own address shows under the box to check');
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      final booked = server.sentTo('/shipments/book').single;
      expect(booked['dropAddress'], 'Guindy, Chennai',
          reason:
              'Rishabh, 21 Oct 2026: keep the typed address; the drag moves only the point');
      expect((booked['drop'] as Map)['lat'], 13.05);
    });

    testWidgets(
        'a searched pickup keeps the address as typed, not the town Google names',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/book?anchorTripId=lane-1',
          findPlace: (place) async => GeocodeOutcome.ok(const LatLng(12.8, 77.7),
              'Bommasandra, Bengaluru, Karnataka 560099, India', 'Bengaluru'));
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = priceByWeight;
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      });
      await tester.pumpAndSettle();
      await tester.enterText(field('Weight'), '80');
      await searchPlace(tester, 'Pickup', 'Plot 12, 4th Cross, Bommasandra');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      expect(tester.widget<TextField>(placeField('Pickup')).controller!.text,
          'Plot 12, 4th Cross, Bommasandra');
      expect(find.text('Pin: Bommasandra, Bengaluru, Karnataka 560099, India'),
          findsWidgets,
          reason: 'the Pin line still shows where the pin went');
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      final booked = server.sentTo('/shipments/book').single;
      expect(booked['pickupAddress'], 'Plot 12, 4th Cross, Bommasandra',
          reason: 'the plot number is what the carrier needs to collect');
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

    testWidgets('Pay opens payment in one tap, with no sheet first',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      });
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(find.byType(NvSheet), findsNothing,
          reason: 'Rishabh: from a filled form, paying is one tap');
      expect(server.countOf('/shipments/book'), 1,
          reason: 'the one tap runs the existing booking call');
      final booked = server.sentTo('/shipments/book').single;
      expect(booked['weightKg'], 80, reason: 'the priced weight is booked');
      expect(booked['pickupAddress'], 'Bommasandra, Bengaluru');
      expect(find.text('Shipment shipment-9'), findsOneWidget,
          reason: 'after booking, the shipment opens');
    });

    testWidgets('one tap on Pay opens the payment provider with the amount',
        (tester) async {
      final opened = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('razorpay_flutter'), (call) async {
        if (call.method == 'open') opened.add(call.arguments as Map);
        return call.method == 'open'
            ? {
                'type': 1,
                'data': {'code': 2, 'message': 'Payment cancelled'}
              }
            : null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('razorpay_flutter'), null));
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {
          'status': 'CREATED',
          'amountPaise': 264000,
          'razorpayOrderId': 'order_synthetic'
        },
        'razorpayKeyId': 'rzp_test_synthetic',
      });
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1),
          reason: 'Rishabh: Pay goes straight to the payment step');
      expect(opened.single.toString(), contains('264000'),
          reason: 'the provider is opened for the amount on Pay');
    });

    testWidgets(
        'too heavy shows the plain sentence under Weight, never HTTP text',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {'error': 'insufficient_capacity'}, 400);
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This trip does not have enough capacity for that weight. Enter less weight, or choose another trip.'),
          findsOneWidget,
          reason: 'copy.md: too heavy, replaces "HTTP 400"');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no raw codes');
      expect(find.text('Choose another trip'), findsOneWidget,
          reason: 'copy.md: the way to another lane');
    });

    testWidgets('after a no-capacity refusal, the trip is loaded again and its capacity is current',
        (tester) async {
      final server = await showPricedBook(tester);
      expect(find.text('Capacity remaining: 25 kg'), findsOneWidget,
          reason: '105 kg left when the screen opened, less the 80 kg typed');
      final lanesBefore = server.countOf('/anchor-trips/lane-1');
      server.answer('/shipments/book', {'error': 'insufficient_capacity'}, 400);
      server.answer('/anchor-trips/lane-1', {'trip': lane(reservedKg: 950)});
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(server.countOf('/anchor-trips/lane-1'), lanesBefore + 1);
      expect(find.text("30 kg more than this trip's capacity"), findsOneWidget,
          reason: 'someone else booked 55 kg meanwhile: 50 kg are left, not 105');
    });

    // The booking exists before checkout opens, so after checkout the shipper goes to it and Pay is
    // never offered again: a second Pay would book a second shipment.
    Future<(FakeServer, List<String>)> payThroughCheckout(WidgetTester tester,
        {required Map<String, dynamic> checkoutAnswer,
        bool confirmFails = false}) async {
      final announced = watchAnnouncements(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('razorpay_flutter'),
          (call) async => call.method == 'open' ? checkoutAnswer : null);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('razorpay_flutter'), null));
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {
          'status': 'CREATED',
          'amountPaise': 264000,
          'razorpayOrderId': 'order_synthetic'
        },
        'razorpayKeyId': 'rzp_test_synthetic',
      });
      if (confirmFails) {
        server.answer(
            '/v1/payments/razorpay/confirm', {'error': 'internal_error'}, 500);
      }
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      return (server, announced);
    }

    testWidgets(
        'a closed or failed checkout opens the unpaid booking instead of offering Pay again',
        (tester) async {
      final (server, announced) =
          await payThroughCheckout(tester, checkoutAnswer: {
        'type': 1,
        'data': {'code': 2, 'message': 'Payment cancelled'}
      });
      expect(server.countOf('/shipments/book'), 1);
      expect(find.text('Shipment shipment-9'), findsOneWidget,
          reason:
              'the booking already exists; tapping Pay again would book a second shipment');
      expect(find.text('Payment did not go through. This shipment is not paid.'),
          findsOneWidget,
          reason: 'says why the shipment opened, in plain words');
      expect(find.textContaining('Payment cancelled'), findsNothing,
          reason: "the payment provider's own message is not shown");
      expect(announced,
          contains('Payment did not go through. This shipment is not paid.'),
          reason: 'never announce "Booked. Waiting" for an unpaid booking');
    });

    testWidgets(
        'a payment the app could not confirm opens the shipment without saying it is paid',
        (tester) async {
      final (_, announced) =
          await payThroughCheckout(tester, confirmFails: true, checkoutAnswer: {
        'type': 0,
        'data': {
          'razorpay_order_id': 'order_synthetic',
          'razorpay_payment_id': 'pay_synthetic',
          'razorpay_signature': 'signature_synthetic'
        }
      });
      expect(find.text('Shipment shipment-9'), findsOneWidget);
      expect(
          announced,
          contains(
              'Booked. We could not confirm the payment yet. The shipment shows whether it went through.'),
          reason:
              'the confirm call failed, so the app does not know the payment is held');
    });

    testWidgets(
        'a booking whose payment never started is not announced as paid',
        (tester) async {
      final announced = watchAnnouncements(tester);
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CREATED', 'amountPaise': 264000},
      });
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(find.text('Shipment shipment-9'), findsOneWidget);
      expect(
          announced,
          contains(
              'Booked, but payment did not start. This shipment is not paid.'),
          reason: 'checkout never opened, so nothing was paid');
    });

    testWidgets(
        'a searched place with no point is never priced; the place waits for a search',
        (tester) async {
      final server = await showShipperApp(tester, searchedBook,
          initialExtra: SearchedPlaces(
              pickup: (
                  words: 'Bommasandra, Bengaluru', point: null, pinAddress: null),
              drop: searchedPlaces.drop));
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = priceByWeight;
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(placeField('Pickup')).controller!.text,
          'Bommasandra, Bengaluru',
          reason: 'the searched words stay');
      expect(server.countOf('/shipments/quote'), 0,
          reason: 'a place with no point is never sent');
      expect(find.text('To see the price, search for the pickup.'),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: placeBox('Pickup'), matching: find.byTooltip('Search for place')));
      await tester.pumpAndSettle();
      expect((server.sentTo('/shipments/quote').single['pickup'] as Map)['lat'],
          12.8,
          reason: 'the searched place is priced');
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

    testWidgets(
        'Pay, the full-price line and the contact line are on screen without scrolling at 360 x 800',
        (tester) async {
      await showPricedBook(tester, height: 800);
      for (final words in [
        'Book and pay ₹2,640',
        fullPriceLine,
        failedPaymentLine,
        contactAbovePay
      ]) {
        final shown = tester.getRect(find.text(words));
        expect(shown.top >= 0 && shown.bottom <= 800, isTrue,
            reason:
                'decisions.md 8 and no hidden costs: "$words" shows beside Pay at 360 x 800');
      }
    });

    testWidgets(
        'Book and pay names the total, with the room and cancel line directly above it',
        (tester) async {
      await showPricedBook(tester);
      expect(bookButton(tester).label, 'Book and pay ₹2,640',
          reason: 'Rishabh: one tap books and opens payment, and the label says both');
      final button = tester.getRect(find.text('Book and pay ₹2,640'));
      final cancelLine = tester.getRect(find.text(contactAbovePay));
      expect(cancelLine.bottom, lessThanOrEqualTo(button.top),
          reason: 'Rishabh: the line sits directly above the button');
      expect(tester.getRect(find.text(fullPriceLine)).bottom,
          lessThanOrEqualTo(cancelLine.top),
          reason: 'the full-price line stays, above the cancel line');
      final failedPayment = tester.getRect(find.text(failedPaymentLine));
      expect(failedPayment.top,
          greaterThanOrEqualTo(tester.getRect(find.text(fullPriceLine)).bottom),
          reason: 'owner, 21 Oct 2026: what a failed payment means sits by the full-price line');
      expect(failedPayment.bottom, lessThanOrEqualTo(cancelLine.top),
          reason: 'the cancel line stays the one directly above the button');
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
