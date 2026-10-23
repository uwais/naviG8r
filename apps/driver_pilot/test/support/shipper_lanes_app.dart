// The shipper app on a fake server, as the Book a trip and Book tests open it: a lane, its price,
// and the place boxes. Names, places and amounts are the mockups' synthetic ones.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/location_editor.dart';
import 'package:driver_pilot/shipper/book_a_lane.dart';
import 'package:driver_pilot/shipper/find_a_lane.dart';
import 'package:driver_pilot/shipper/shipper_home.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/google_geocoding.dart';
import 'package:driver_pilot/ui/pending_copy.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_action_bar.dart';
import 'package:driver_pilot/ui/nv_button.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'mock_api.dart';

/// A lane with no town pins, so Book's 15 km rule leaves the synthetic places where they are, as the
/// server does for such a trip. Tests of the rule add the pins (shipper_book_far_pin_test.dart).
Map<String, dynamic> lane(
        {String id = 'lane-1',
        String from = 'Bengaluru',
        String to = 'Chennai',
        String carrier = 'Ravi Roadways',
        num capacityKg = 1000,
        num reservedKg = 895,
        String status = 'OPEN'}) =>
    {
      'id': id,
      'originCity': from,
      'destCity': to,
      'carrierDisplayName': carrier,
      'vehicleClass': 'MEDIUM',
      'capacityKg': capacityKg,
      'reservedKg': reservedKg,
      'status': status,
      'windowStart': '2026-10-18T03:30:00.000Z',
      'windowEnd': '2026-10-19T12:00:00.000Z',
    };

/// What the fake server answers, by path; anything else is an empty 200.
class FakeServer {
  final requests = <RequestOptions>[];
  final answers = <String, FutureOr<ResponseBody> Function(RequestOptions)>{};

  int countOf(String path) =>
      requests.where((request) => request.uri.path == path).length;

  List<Map> sentTo(String path) => [
        for (final request in requests)
          if (request.uri.path == path) request.data as Map
      ];

  void answer(String path, Object body, [int status = 200]) =>
      answers[path] = (_) => jsonResponse(body, status);
}

/// Finds every place at one point, named exactly as typed.
Future<GeocodeOutcome> findAnyPlace(String place) async =>
    GeocodeOutcome.ok(const LatLng(12.8, 77.7), place, place);

/// The place box titled [title] (Pickup or Drop) and its text box.
Finder placeBox(String title) =>
    find.widgetWithText(LocationEndpointEditor, title);
Finder placeField(String title) =>
    find.descendant(of: placeBox(title), matching: find.byType(TextField));

/// Types [words] into a place box and taps its search, as a shipper finds a place.
Future<void> searchPlace(
    WidgetTester tester, String title, String words) async {
  await tester.enterText(placeField(title), words);
  final search = find.descendant(
      of: placeBox(title), matching: find.byTooltip('Search for place'));
  await tester.ensureVisible(search);
  await tester.pumpAndSettle();
  await tester.tap(search);
  await tester.pumpAndSettle();
}

/// The map pin inside the place box titled [title].
Marker pinIn(WidgetTester tester, String title) => tester
    .widget<GoogleMap>(
        find.descendant(of: placeBox(title), matching: find.byType(GoogleMap)))
    .markers
    .single;

/// Lets requests that are answered run while one is still waiting; pumpAndSettle would wait
/// forever on the waiting button's progress ring.
Future<void> pumpWhileWaiting(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A phone 360 dp wide, or [width] for the desktop layout. [height] is 800 for "visible without
/// scrolling" checks; taller elsewhere, because the test font draws every letter a full square
/// wide and lists build only what shows. A null [findPlace] leaves Book its own Google search, sent
/// with [mapsApiKey].
Future<FakeServer> showShipperApp(WidgetTester tester, String start,
    {double height = 2000,
    double width = 360,
    PlaceFinder? findPlace = findAnyPlace,
    PinNamer namePin = GoogleGeocodingService.reverseAddress,
    Object? initialExtra,
    String? mapsApiKey}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
  api = Api('http://test');
  CustomerSession.skipRefreshInTests = true;
  addTearDown(() => CustomerSession.skipRefreshInTests = false);
  CustomerSession.applyForTest(
      userFullName: 'Priya Raman',
      userPhone: '9845012345',
      customerOrgId: 'org-sharma',
      customerOrgName: 'Sharma Textiles',
      customerRole: 'CUSTOMER_MEMBER');
  // What every shipper holds on the server (api/rbac.ts), beyond applyForTest's defaults.
  AuthorizationSession.principal!['permissions'] = [
    ...AuthorizationSession.principal!['permissions'] as List,
    'eway_bill.write',
    'eway_bill.add_truck',
    'notification.read',
  ];
  api.selectOrganization('org-sharma');
  final server = FakeServer();
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    server.requests.add(request);
    final answer = server.answers[request.uri.path];
    return answer == null ? jsonResponse({}) : answer(request);
  });
  final router =
      GoRouter(initialLocation: start, initialExtra: initialExtra, routes: [
    GoRoute(
        path: '/customer',
        builder: (_, __) => const CustomerHomeScreen(),
        routes: [
          GoRoute(
              path: 'trips',
              builder: (_, state) => CustomerTripsScreen(
                  startWithMatch: state.uri.queryParameters['tab'] == 'match',
                  findPlace: findPlace ?? findAnyPlace,
                  namePin: namePin)),
          GoRoute(
              path: 'book',
              builder: (_, state) => CustomerBookShipmentScreen.fromQuery(
                  state.uri.queryParameters,
                  extra: state.extra,
                  findPlace: findPlace,
                  namePin: namePin,
                  mapsApiKey: mapsApiKey)),
          GoRoute(
              path: 'shipments',
              builder: (_, __) => const Text('Shipments list')),
          GoRoute(
              path: 'shipments/:id',
              // A Scaffold, as the real shipment screen has, so a snack bar shown on arrival appears.
              builder: (_, state) => Scaffold(
                  body: Text('Shipment ${state.pathParameters['id']}'))),
        ]),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(
      MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
  return server;
}

/// The text box inside the NvField labelled [label].
Finder field(String label) => find.descendant(
    of: find.widgetWithText(NvField, label), matching: find.byType(TextField));

/// Book for lane-1 as a lane card opens it after a match search for 80 kg. The places come as the
/// router's extra, [searchedPlaces]; the link holds no address.
const searchedBook = '/customer/book?anchorTripId=lane-1&weightKg=80';

const searchedPlaces = SearchedPlaces(
    pickup: (
        words: 'Bommasandra, Bengaluru',
        point: LatLng(12.8, 77.7),
        pinAddress: (address: 'Bommasandra, Bengaluru, Karnataka 560099, India', lookupFailed: false)),
    drop: (
        words: 'Guindy, Chennai',
        point: LatLng(13.0, 80.2),
        pinAddress: (address: 'Guindy, Chennai, Tamil Nadu 600032, India', lookupFailed: false)));

/// The fake price: ₹33 a kg, so 80 kg is ₹2,640 and 90 kg is ₹2,970.
ResponseBody priceByWeight(RequestOptions request) => jsonResponse({
      'quote': {'grossPaise': ((request.data as Map)['weightKg'] as int) * 3300}
    });

/// Book opened from a match result; the price comes with no tap.
Future<FakeServer> showPricedBook(WidgetTester tester,
    {double height = 2000, double width = 360}) async {
  final server =
      await showShipperApp(tester, searchedBook,
          height: height, width: width, initialExtra: searchedPlaces);
  server.answer('/anchor-trips/lane-1', {'trip': lane()});
  server.answers['/shipments/quote'] = priceByWeight;
  await tester.pumpAndSettle();
  return server;
}

const contactAbovePay =
    'To cancel, contact ${PendingCopy.changeOrCancelContact}.';

/// The one bottom button on Book.
NvButton bookButton(WidgetTester tester) => tester.widget<NvButton>(find
    .descendant(
        of: find.byType(NvActionBar), matching: find.byType(NvButton))
    .last);

const fullPriceLine = 'Full price. Nothing is added at payment.';
