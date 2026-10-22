// PR 4 of the redesign: Book's pickup and drop, where the pin decides the place and the price, and
// the typed words go to the driver (sh-book-*). Names, places and amounts are the mockups' synthetic
// ones.
import 'dart:async';

import 'package:driver_pilot/shipper/book_a_lane.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/shipper_lanes_app.dart';
import 'support/shipper_screen_checks.dart';

void main() {
  group('Book', () {
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
      expect(find.text('Pickup: Plot 12, Bommasandra'), findsOneWidget,
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

    testWidgets('words typed after the pins check shows are the words it shows',
        (tester) async {
      await showPricedBook(tester, height: 4000);
      expect(find.text('Pickup: Bommasandra, Bengaluru'), findsOneWidget,
          reason: 'the check is there before any typing');
      await tester.enterText(placeField('Pickup'), 'Plot 12, Bommasandra');
      await tester.pumpAndSettle();
      expect(find.text('Pickup: Plot 12, Bommasandra'), findsOneWidget,
          reason: 'review: the check showed the words from before the typing');
      expect(find.text('Pickup: Bommasandra, Bengaluru'), findsNothing);
    });

    testWidgets(
        'a Pin line for each place sits just above Book and pay, one line on screen and whole to a screen reader',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await showPricedBook(tester, height: 4000);
      Finder inBar(Finder finder) =>
          find.descendant(of: find.byType(NvActionBar), matching: finder);
      const pickupLine =
          'Pickup pin in Bengaluru: Bommasandra, Bengaluru, Karnataka 560099, India';
      const dropLine = 'Drop pin in Chennai: Guindy, Chennai, Tamil Nadu 600032, India';
      for (final line in [pickupLine, dropLine]) {
        expect(inBar(find.text(line)), findsOneWidget,
            reason: 'owner, 21 Oct 2026: "Pin lines just above Book and pay"');
        final shown = tester.widget<Text>(inBar(find.text(line)));
        expect(shown.maxLines, 1,
            reason: 'kept short: one line each, the town first so the cut never hides it');
        expect(shown.overflow, TextOverflow.ellipsis);
        expect(find.bySemanticsLabel(line), findsOneWidget,
            reason: 'the full address is read out');
      }
      final button = tester.getRect(find.text('Book and pay ₹2,640'));
      final drop = tester.getRect(inBar(find.text(dropLine)));
      expect(tester.getRect(inBar(find.text(pickupLine))).bottom,
          lessThanOrEqualTo(drop.top));
      expect(drop.bottom, lessThanOrEqualTo(button.top));
      expect(button.top - drop.bottom, lessThan(40),
          reason: 'directly above the button, nothing between');
      expect(find.text('Check the pins before you pay'), findsOneWidget,
          reason: 'the map card stays, below the place boxes');
      semantics.dispose();
    });

    testWidgets('Book and pay waits while a place search is out, then goes on',
        (tester) async {
      final found = Completer<GeocodeOutcome>();
      final server = await showShipperApp(tester, searchedBook,
          findPlace: (_) => found.future, initialExtra: searchedPlaces);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = priceByWeight;
      await tester.pumpAndSettle();
      expect(bookButton(tester).onPressed, isNotNull);
      await tester.enterText(placeField('Drop'), 'Adyar, Chennai');
      await tester.tap(find.descendant(
          of: placeBox('Drop'), matching: find.byTooltip('Search for place')));
      await pumpWhileWaiting(tester);
      expect(bookButton(tester).onPressed, isNull,
          reason: 'review: the answer would move the pin after paying');
      expect(
          find.descendant(
              of: find.byType(NvActionBar),
              matching: find.text('Searching for the place…')),
          findsOneWidget,
          reason: 'a disabled button says why');
      found.complete(GeocodeOutcome.ok(const LatLng(13.0, 80.25),
          'Adyar, Chennai, Tamil Nadu 600020, India', 'Chennai'));
      await tester.pumpAndSettle();
      expect(bookButton(tester).onPressed, isNotNull);
      expect((server.sentTo('/shipments/quote').last['drop'] as Map)['lng'], 80.25,
          reason: 'the place found is priced before booking');
    });

    testWidgets('the pins on Book are labelled Pickup and Drop', (tester) async {
      await showPricedBook(tester, height: 4000);
      final bothPins = tester
          .widgetList<GoogleMap>(find.byType(GoogleMap))
          .where((map) => map.markers.length == 2)
          .single
          .markers;
      expect(bothPins.map((pin) => pin.infoWindow.title), unorderedEquals(['Pickup', 'Drop']),
          reason: 'review: which pin is which, when tapped');
      expect(pinIn(tester, 'Pickup').infoWindow.title, 'Pickup');
      expect(pinIn(tester, 'Drop').infoWindow.title, 'Drop');
    });

    testWidgets('the place boxes ask for the address for the driver', (tester) async {
      await showPricedBook(tester);
      for (final title in ['Pickup', 'Drop']) {
        final box = tester.widget<TextField>(placeField(title)).decoration!;
        expect(box.labelText, 'Address for the driver', reason: title);
        expect(box.hintText, 'House or plot, street, area', reason: title);
      }
    });

    testWidgets(
        'a pin naming still out when its box scrolls off screen still lets Book and pay go on',
        (tester) async {
      final address = Completer<GeocodeOutcome>();
      final server = await showShipperApp(tester, searchedBook,
          height: 800,
          namePin: (_) => address.future,
          initialExtra: searchedPlaces);
      server.answer('/anchor-trips/lane-1', {'trip': lane()});
      server.answers['/shipments/quote'] = priceByWeight;
      await tester.pumpAndSettle();
      await scrollTo(tester,
          find.descendant(of: placeBox('Pickup'), matching: find.byType(GoogleMap)));
      pinIn(tester, 'Pickup').onDragEnd!(const LatLng(12.85, 77.65));
      await tester.pumpAndSettle();
      expect(bookButton(tester).onPressed, isNull,
          reason: 'waiting for the pin to be named');
      final list = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      list.jumpTo(list.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(placeBox('Pickup'), findsNothing, reason: 'the box is off screen');
      address.complete(GeocodeOutcome.ok(const LatLng(12.85, 77.65),
          'Electronic City, Bengaluru, Karnataka 560100, India', 'Bengaluru'));
      await tester.pumpAndSettle();
      expect(bookButton(tester).onPressed, isNotNull,
          reason: 'review: a box scrolled off screen lost the naming, and Book and pay waited for ever');
      expect(find.text('Pin: Electronic City, Bengaluru, Karnataka 560100, India'),
          findsOneWidget,
          reason: 'the pins check shows the address the pin was named');
    });
  });
}
