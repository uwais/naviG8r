// A street address must never sit in the browser's history. The match search hands its places to
// Book in memory, not in the link; reopening the link opens Book with empty place boxes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/shipper_lanes_app.dart';

void main() {
  testWidgets('Book from a match search keeps the places out of the link',
      (tester) async {
    final server = await showShipperApp(tester, '/customer/trips?tab=match');
    server.answer('/v1/customer/eligible-anchor-trips', {
      'trips': [
        {
          'trip': lane(),
          'eligibility': {'eligible': true}
        },
      ]
    });
    server.answer('/anchor-trips/lane-1', {'trip': lane()});
    await tester.pumpAndSettle();
    await searchPlace(tester, 'Pickup', 'Plot 12, Bommasandra, Bengaluru');
    await searchPlace(tester, 'Drop', 'Guindy, Chennai');
    await tester.enterText(field('Weight'), '80');
    await tester.tap(find.text('Find trips'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bengaluru to Chennai'));
    await tester.pumpAndSettle();

    expect(find.text('Book this trip'), findsOneWidget);
    expect(tester.widget<TextField>(placeField('Pickup')).controller!.text,
        'Plot 12, Bommasandra, Bengaluru',
        reason: 'Book still gets the searched pickup');
    final router = GoRouter.of(tester.element(find.text('Book this trip')));
    final link = router.routeInformationProvider.value.uri.toString();
    expect(link, isNot(contains('Bommasandra')));
    expect(link, isNot(contains('Guindy')));
    expect(link, isNot(contains('Lat')), reason: 'no map points either');

    // As a reload or a pasted link: the same address, with nothing in memory.
    router.go('/customer');
    await tester.pumpAndSettle();
    router.go(link);
    await tester.pumpAndSettle();
    expect(find.text('Book this trip'), findsOneWidget,
        reason: 'the link alone still opens Book');
    expect(tester.widget<TextField>(placeField('Pickup')).controller!.text, '',
        reason: 'opened from the link alone, the places are typed again');
  });
}
