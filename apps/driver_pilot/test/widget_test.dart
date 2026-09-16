import "dart:math" as math;

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:driver_pilot/driver_flow.dart";
import "package:driver_pilot/driver_theme.dart";

/// The Android landing screen.
///
/// The previous version of this file asserted the nav labels of the legacy `/pilot-lab`
/// surface (Home, Register, Login, Trips, Publish). The app stopped launching there when
/// `/driver` became the Android entry point, so it had been failing on every run since —
/// unnoticed, because no CI workflow runs Flutter tests.
///
/// These pump the intent cards directly rather than the whole app: `DriverWelcomeScreen`
/// calls `DriverSession.refresh()` in `initState`, which needs the network and a
/// `flutter_secure_storage` platform channel that does not exist under `flutter test`.
/// Covering the three resolved states needs those two seams injectable first.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(body: child),
      );

  testWidgets("intent card shows its title and subtitle and is tappable", (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(
      ListView(
        children: [
          IntentCard(
            icon: Icons.local_shipping_outlined,
            title: "I own a truck or transport business",
            subtitle: "Create your carrier and add your first vehicle",
            onTap: () => taps++,
          ),
        ],
      ),
    ));

    expect(find.text("I own a truck or transport business"), findsOneWidget);
    expect(find.text("Create your carrier and add your first vehicle"), findsOneWidget);

    await tester.tap(find.byType(IntentCard));
    await tester.pump();
    expect(taps, 1);
  });

  test("secondary text on the scaffold clears WCAG AA", () {
    double channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    double luminance(Color c) =>
        0.2126 * channel(c.red / 255) + 0.7152 * channel(c.green / 255) + 0.0722 * channel(c.blue / 255);
    double ratio(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    // Guards the reason mutedOnBackground exists. Deliberately does not assert that
    // `muted` fails: darkening it later would be an improvement, not a regression.
    expect(ratio(DriverTheme.mutedOnBackground, DriverTheme.background), greaterThan(4.5));
    expect(ratio(DriverTheme.navy, DriverTheme.background), greaterThan(4.5));
  });
}
