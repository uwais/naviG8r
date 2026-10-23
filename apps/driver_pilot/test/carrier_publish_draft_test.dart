// The Publish draft (ca-publish, PR 7 of the redesign): what is kept when the office leaves the form, and
// when it starts empty again.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'support/carrier_office_screens.dart';
import 'support/mock_api.dart';

void main() {
  setUp(() => GeolocatorPlatform.instance = NoLocation());
  tearDown(DriverSession.clearCarrierCache);

  group('Publish (ca-publish)', () {
    group('the draft', () {
      Widget publish() => DriverPublishTripScreen(
          findPlace: (place) async =>
              GeocodeOutcome.ok(const LatLng(13.07, 77.8), '$place, Karnataka'));
      List<String> fieldTexts(WidgetTester tester) => [
            for (final field
                in tester.widgetList<TextField>(find.byType(TextField)))
              field.controller!.text
          ];

      Future<void> fillIn(WidgetTester tester) async {
        for (final (index, place) in [(0, 'Hoskote'), (1, 'Kolar')]) {
          await tester.enterText(find.byType(TextField).at(index), place);
          await tester.tap(find.byTooltip('Search for place').at(index));
          await tester.pumpAndSettle();
        }
        for (final _ in [1, 2]) {
          await tester.tap(find.text('Choose a date').first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.widgetWithText(ChoiceChip, 'Medium'));
        await tester.enterText(find.byType(TextField).last, '1000');
        await tester.pumpAndSettle();
      }

      testWidgets('going to another tab and back keeps what was typed',
          (tester) async {
        signInWith(Server(allowed: ownerAllowed));
        final router =
            await mount(tester, publish(), size: const Size(800, 3000));
        await fillIn(tester);
        router.go('/driver/loads');
        await tester.pumpAndSettle();
        router.go('/screen');
        await tester.pumpAndSettle();
        expect(fieldTexts(tester),
            ['Hoskote', 'Kolar', '1000'],
            reason: 'owner run: leaving Publish wiped the form');
        expect(find.byType(GoogleMap), findsNWidgets(3),
            reason: 'both places keep their points, so their maps and the route map show');
        expect(find.text('Choose a date'), findsNothing,
            reason: 'both leaving days are kept');
        expect(
            tester
                .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Medium'))
                .selected,
            isTrue);
      });

      testWidgets('publishing, signing out or another sign-in starts empty',
          (tester) async {
        final server = signInWith(Server(allowed: ownerAllowed));
        var router =
            await mount(tester, publish(), size: const Size(800, 3000));
        await fillIn(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
        await tester.pumpAndSettle();
        expect(server.sent, hasLength(1));
        router.go('/screen');
        await tester.pumpAndSettle();
        expect(fieldTexts(tester), ['', '', ''],
            reason: 'a published trip is not a draft');

        await fillIn(tester);
        router.go('/driver/loads');
        await tester.pumpAndSettle();
        // The same account signing out and back in.
        signInWith(Server(allowed: ownerAllowed));
        router.go('/screen');
        await tester.pumpAndSettle();
        expect(fieldTexts(tester), ['', '', ''],
            reason: 'a sign-out ends the draft, even for the same account');
        expect(find.text('Choose a date'), findsNWidgets(2));
      });

      testWidgets('leaving while a publish is still sending keeps no draft to send again',
          (tester) async {
        final server = signInWith(Server(allowed: ownerAllowed));
        final answered = api.dio.httpClientAdapter as MockApiAdapter;
        final publishAnswer = Completer<ResponseBody>();
        api.dio.httpClientAdapter = MockApiAdapter((request) {
          if (request.method == 'GET') return answered.handle(request);
          server.sent.add(request);
          return publishAnswer.future;
        });
        final router =
            await mount(tester, publish(), size: const Size(800, 3000));
        await fillIn(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(server.sent, hasLength(1));
        router.go('/driver/loads');
        await tester.pumpAndSettle();
        router.go('/screen');
        await tester.pumpAndSettle();
        expect(fieldTexts(tester), ['', '', ''],
            reason: 'review: the kept draft let the same trip be published twice');
        publishAnswer.complete(jsonResponse({'trip': null}));
        await tester.pumpAndSettle();
      });

      testWidgets('a draft kept past midnight drops the days that have gone',
          (tester) async {
        final server = signInWith(Server(allowed: ownerAllowed));
        final router =
            await mount(tester, publish(), size: const Size(800, 3000));
        // Both days are today, the earliest the picker offers.
        await fillIn(tester);
        router.go('/driver/loads');
        await tester.pumpAndSettle();
        currentTime = () => DateTime.now().add(const Duration(days: 1));
        addTearDown(() => currentTime = DateTime.now);
        router.go('/screen');
        await tester.pumpAndSettle();
        expect(fieldTexts(tester),
            ['Hoskote', 'Kolar', '1000'],
            reason: 'the places and the room are still good');
        expect(find.text('Choose a date'), findsNWidgets(2),
            reason: 'review: yesterday was restored and sent to the server');
        await tester.tap(find.widgetWithText(FilledButton, 'Add trip'));
        await tester.pumpAndSettle();
        expect(server.sent, isEmpty);
        expect(find.text('Choose the first day the truck can leave.'),
            findsOneWidget);
      });
    });
  });
}
