// Search and filters on Book a trip (owner request, 18 Nov 2026): town words, a day, carrier and truck size chips
// built from the trips shown, Clear all, and an empty result that says what to change. Names and places are the
// mockups' synthetic ones.
import 'package:driver_pilot/shipper/trip_filters.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shipper_lanes_app.dart';

/// An instant [days] from now, as the server writes a window: the app reads it in India.
String _inDays(int days, {int hourUtc = 6}) {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day + days, hourUtc)
      .toIso8601String();
}

Map<String, dynamic> _trip(String id,
        {required int leavesInDays,
        String from = 'Bengaluru',
        String to = 'Chennai',
        String carrier = 'Ravi Roadways',
        String size = 'MEDIUM'}) =>
    {
      ...lane(id: id, from: from, to: to, carrier: carrier),
      'vehicleClass': size,
      'windowStart': _inDays(leavesInDays),
      'windowEnd': _inDays(leavesInDays + 1),
    };

final _trips = [
  _trip('later', leavesInDays: 9, to: 'Hyderabad', carrier: 'Deccan Movers', size: 'LARGE'),
  _trip('soonest', leavesInDays: 1),
  _trip('middle', leavesInDays: 4, from: 'Mysuru', to: 'Hassan', carrier: 'Kaveri Logistics'),
];

Finder _search() => find.descendant(
    of: find.widgetWithText(NvField, 'Search towns'),
    matching: find.byType(TextField));

Future<void> _openBrowse(WidgetTester tester, {double height = 2400}) async {
  final server =
      await showShipperApp(tester, '/customer/trips', height: height);
  server.answer('/anchor-trips', {'trips': _trips});
  await tester.pumpAndSettle();
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  group('Book a trip, All trips', () {
    testWidgets('trips come soonest to leave first, whatever order the server sent',
        (tester) async {
      await _openBrowse(tester);
      final soonest = _top(tester, 'Bengaluru to Chennai');
      final middle = _top(tester, 'Mysuru to Hassan');
      final later = _top(tester, 'Bengaluru to Hyderabad');
      expect(soonest < middle && middle < later, isTrue);
      expect(find.textContaining('Showing'), findsNothing,
          reason: 'no count line until a filter is on');
      expect(find.text('Clear all filters'), findsNothing);
    });

    testWidgets('the search box matches the town a trip leaves from or goes to',
        (tester) async {
      await _openBrowse(tester);
      await tester.enterText(_search(), 'hassan');
      await tester.pumpAndSettle();
      expect(find.text('Mysuru to Hassan'), findsOneWidget);
      expect(find.text('Bengaluru to Chennai'), findsNothing);
      expect(find.text('Showing 1 of 3 trips.'), findsOneWidget);

      await tester.enterText(_search(), 'Bengal');
      await tester.pumpAndSettle();
      expect(find.text('Bengaluru to Chennai'), findsOneWidget);
      expect(find.text('Bengaluru to Hyderabad'), findsOneWidget);
      expect(find.text('Mysuru to Hassan'), findsNothing);
    });

    testWidgets(
        'carrier and truck size chips come from the trips shown, A to Z and small to large, with Any first',
        (tester) async {
      await _openBrowse(tester);
      final carriers = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((chip) => ((chip.label as Text).data))
          .toList();
      expect(carriers, [
        'Any carrier',
        'Deccan Movers',
        'Kaveri Logistics',
        'Ravi Roadways',
        'Any size',
        'Medium',
        'Large',
      ], reason: 'no Small chip, since no trip shown is small');
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Any carrier'))
              .selected,
          isTrue,
          reason: 'nothing is filtered until the shipper chooses');

      await _tapChip(tester, 'Kaveri Logistics');
      expect(find.text('Mysuru to Hassan'), findsOneWidget);
      expect(find.text('Bengaluru to Chennai'), findsNothing);

      await _tapChip(tester, 'Any carrier');
      await _tapChip(tester, 'Large');
      expect(find.text('Bengaluru to Hyderabad'), findsOneWidget);
      expect(find.text('Showing 1 of 3 trips.'), findsOneWidget);
    });

    testWidgets('one carrier and one size show no chips: one choice is no choice',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips');
      server.answer('/anchor-trips', {
        'trips': [_trip('a', leavesInDays: 1), _trip('b', leavesInDays: 2)]
      });
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNothing);
      expect(_search(), findsOneWidget);
    });

    testWidgets(
        'a day keeps trips that can still leave on it or later; Clear all brings every trip back',
        (tester) async {
      await _openBrowse(tester);
      final day = DateTime.now().toUtc().add(const Duration(days: 5));
      final typed =
          '${day.month.toString().padLeft(2, '0')}/${day.day.toString().padLeft(2, '0')}/${day.year}';
      await tester.tap(find.text('Any day'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byType(Dialog), matching: find.byType(TextField)),
          typed);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Any day'), findsNothing,
          reason: 'the button now names the day');
      expect(find.text('Bengaluru to Hyderabad'), findsOneWidget,
          reason: 'leaves in 9 to 10 days');
      expect(find.text('Mysuru to Hassan'), findsOneWidget,
          reason: 'its last leaving day is 5 days from now, the day chosen');
      expect(find.text('Bengaluru to Chennai'), findsNothing,
          reason: 'its last leaving day is 2 days from now');

      await tester.tap(find.text('Clear all filters'));
      await tester.pumpAndSettle();
      expect(find.text('Any day'), findsOneWidget);
      expect(find.text('Bengaluru to Chennai'), findsOneWidget);
      expect(find.text('Clear all filters'), findsNothing);
    });

    testWidgets('when nothing matches, the list says what to change',
        (tester) async {
      await _openBrowse(tester);
      await tester.enterText(_search(), 'Pune');
      await _tapChip(tester, 'Ravi Roadways');
      expect(find.text('No trips match these filters.'), findsOneWidget);
      expect(find.text('Try other town words or any carrier, or clear all filters.'),
          findsOneWidget);
      expect(find.text('Showing 0 of 3 trips.'), findsOneWidget);
    });

    testWidgets(
        'on a 360 x 640 phone at 200% text the filters fit and every chip and button is 48 dp tall',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await _openBrowse(tester, height: 640);
      expect(tester.takeException(), isNull);
      final list = find
          .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(_search(), 100, scrollable: list);
      await tester.enterText(_search(), 'a');
      await tester.pumpAndSettle();
      for (final label in ['Any day', 'Ravi Roadways', 'Large', 'Clear all filters']) {
        final target = find.text(label);
        await tester.scrollUntilVisible(target, 100, scrollable: list);
        await tester.pumpAndSettle();
        final box = find
            .ancestor(
                of: target,
                matching: find.byWidgetPredicate(
                    (widget) => widget is ChoiceChip || widget is ButtonStyleButton))
            .first;
        expect(tester.getSize(box).height,
            greaterThanOrEqualTo(NvSpace.targetMin),
            reason: '$label is a 48 dp target');
        expect(tester.getRect(box).right, lessThanOrEqualTo(360),
            reason: '$label stays on screen');
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Book a trip, Search by route results', () {
    testWidgets(
        'the filters narrow the results and keep the closest-first order',
        (tester) async {
      final server = await showShipperApp(tester, '/customer/trips?tab=match',
          height: 2400);
      server.answer('/v1/customer/eligible-anchor-trips', {
        'trips': [
          for (final trip in [_trips[0], _trips[2], _trips[1]])
            {'trip': trip, 'eligibility': {'eligible': true}},
        ]
      });
      await tester.pumpAndSettle();
      await searchPlace(tester, 'Pickup', 'Bommasandra, Bengaluru');
      await searchPlace(tester, 'Drop', 'Guindy, Chennai');
      await tester.enterText(field('Weight'), '80');
      await tester.tap(find.text('Find trips'));
      await tester.pumpAndSettle();

      final hyderabad = _top(tester, 'Bengaluru to Hyderabad');
      final chennai = _top(tester, 'Bengaluru to Chennai');
      expect(hyderabad < chennai, isTrue,
          reason: 'the server sent it first, as closest; the filters never re-sort');

      await _tapChip(tester, 'Medium');
      expect(find.text('Bengaluru to Hyderabad'), findsNothing);
      expect(find.text('Bengaluru to Chennai'), findsOneWidget);
      expect(find.text('Mysuru to Hassan'), findsOneWidget);
      expect(find.text('Showing 2 of 3 trips.'), findsOneWidget);
      expect(_top(tester, 'Mysuru to Hassan') < _top(tester, 'Bengaluru to Chennai'),
          isTrue);
    });
  });

  group('TripFilters', () {
    test('a trip whose last leaving day is the chosen day stays; one ending the day before goes', () {
      final filters = TripFilters();
      addTearDown(filters.dispose);
      final endsOn20th = {
        'originCity': 'A',
        'destCity': 'B',
        'windowStart': '2026-12-19T00:00:00+05:30',
        'windowEnd': '2026-12-20T23:59:59+05:30',
      };
      filters.leavesOnOrAfter = DateTime.utc(2026, 12, 20);
      expect(filters.apply([endsOn20th]), [endsOn20th]);
      filters.leavesOnOrAfter = DateTime.utc(2026, 12, 21);
      expect(filters.apply([endsOn20th]), isEmpty);
    });

    test('a window read in India: 20:00 UTC on the 20th is already the 21st', () {
      final filters = TripFilters();
      addTearDown(filters.dispose);
      final trip = {'windowEnd': '2026-12-20T20:00:00Z'};
      filters.leavesOnOrAfter = DateTime.utc(2026, 12, 21);
      expect(filters.apply([trip]), [trip]);
    });

    test('what to change names each filter that is on, in plain words', () {
      final filters = TripFilters();
      addTearDown(filters.dispose);
      filters.townWords.text = 'x';
      filters.leavesOnOrAfter = DateTime.utc(2026, 12, 21);
      filters.carrier = 'Ravi Roadways';
      filters.truckSize = 'LARGE';
      expect(filters.whatToChange,
          'Try other town words, an earlier day, any carrier or any truck size, or clear all filters.');
      filters.clearAll();
      expect(filters.anyOn, isFalse);
    });
  });
}
