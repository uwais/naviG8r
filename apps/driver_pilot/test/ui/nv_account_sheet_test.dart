// The account menu's states from spec/components.md: default, switching and error, plus
// sign out and close. It is the only place to switch company or sign out.
import 'dart:async';

import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_account_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const companies = [
  NvCompany(id: 'org-sharma', name: 'Sharma Textiles', role: 'Shipper'),
  NvCompany(
      id: 'org-ravi', name: 'Ravi Roadways', role: 'Carrier · Dispatcher'),
];

Future<void> openAccountMenu(
  WidgetTester tester, {
  NvSwitchCompany? onSwitch,
  VoidCallback? onSignOut,
  VoidCallback? onAddCompany,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DriverTheme.theme(),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showNvAccountSheet(
              context: context,
              person: 'Priya Raman',
              phone: '+91 98450 12345',
              companies: companies,
              currentCompanyId: 'org-sharma',
              onSwitch: onSwitch ?? (_) async => null,
              onSignOut: onSignOut ?? () {},
              onAddCompany: onAddCompany,
            ),
            child: const Text('Open menu'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open menu'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
      'default shows the person, full phone, companies with the current one chosen',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openAccountMenu(tester, onAddCompany: () {});

    expect(find.text('Priya Raman'), findsOneWidget,
        reason: 'copy.md: the menu names the person');
    expect(find.text('+91 98450 12345'), findsOneWidget,
        reason: 'copy.md: the full phone number is shown');
    expect(find.text('YOUR COMPANIES'), findsOneWidget,
        reason: 'copy.md: companies are under YOUR COMPANIES');
    expect(find.text('Sharma Textiles'), findsOneWidget,
        reason: 'each company is listed');
    expect(find.text('Carrier · Dispatcher'), findsOneWidget,
        reason: 'each company shows the person\'s role there');
    expect(
        tester.getSemantics(find.text('Sharma Textiles')),
        matchesSemantics(
            label: 'Sharma Textiles, Shipper',
            hasCheckedState: true,
            isChecked: true,
            hasEnabledState: true,
            isEnabled: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true),
        reason: 'companies are radio rows; the current one is chosen');
    expect(
        tester.getSemantics(find.text('Ravi Roadways')),
        matchesSemantics(
            label: 'Ravi Roadways, Carrier · Dispatcher',
            hasCheckedState: true,
            isChecked: false,
            hasEnabledState: true,
            isEnabled: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true),
        reason: 'other companies are not chosen');
    expect(find.text('Add a company'), findsOneWidget,
        reason: 'copy.md: Add a company');
    expect(find.text('Register as a carrier, or join one'), findsOneWidget,
        reason: 'copy.md: Add a company says what it does');
    expect(find.text('Sign out'), findsOneWidget,
        reason: 'the menu is the only place to sign out');
    expect(find.text('Close'), findsOneWidget, reason: 'copy.md: Close');
    semantics.dispose();
  });

  testWidgets('without an add-company action the row is not shown',
      (tester) async {
    await openAccountMenu(tester);

    expect(find.text('Add a company'), findsNothing,
        reason: 'no row for an action the app cannot do yet');
  });

  testWidgets('switching shows progress on the chosen company, then closes',
      (tester) async {
    final switchDone = Completer<String?>();
    final requested = <String>[];
    await openAccountMenu(tester, onSwitch: (id) {
      requested.add(id);
      return switchDone.future;
    });

    await tester.tap(find.text('Ravi Roadways'));
    await tester.pump();
    expect(requested, ['org-ravi'], reason: 'tapping a company switches to it');
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the chosen company shows it is switching');
    await tester.tap(find.text('Sharma Textiles'));
    await tester.pump();
    expect(requested, ['org-ravi'],
        reason: 'no second switch starts while one is running');

    switchDone.complete(null);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('YOUR COMPANIES'), findsNothing,
        reason: 'the menu closes once the switch worked');
  });

  testWidgets(
      'a failed switch stays open with the reason and the old company chosen',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openAccountMenu(tester,
        onSwitch: (_) async =>
            'Could not reach NaviG8r. Check your connection and try again.');

    await tester.tap(find.text('Ravi Roadways'));
    await tester.pump();
    await tester.pump();
    expect(
        find.text(
            'Could not reach NaviG8r. Check your connection and try again.'),
        findsOneWidget,
        reason: 'the reason given by the app is shown');
    expect(find.text('YOUR COMPANIES'), findsOneWidget,
        reason: 'the menu stays open on error');
    expect(
        tester.getSemantics(find.text('Sharma Textiles')),
        matchesSemantics(
            label: 'Sharma Textiles, Shipper',
            hasCheckedState: true,
            isChecked: true,
            hasEnabledState: true,
            isEnabled: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true),
        reason: 'the company in use stays chosen after a failed switch');
    semantics.dispose();
  });

  testWidgets('Sign out closes the menu and signs out', (tester) async {
    var signedOut = false;
    await openAccountMenu(tester, onSignOut: () => signedOut = true);

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(signedOut, isTrue, reason: 'Sign out signs out');
    expect(find.text('YOUR COMPANIES'), findsNothing,
        reason: 'the menu closes on sign out');
  });

  testWidgets('Close closes the menu and changes nothing', (tester) async {
    var switched = false;
    await openAccountMenu(tester, onSwitch: (_) async {
      switched = true;
      return null;
    });

    await tester.tap(find.text('Close'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('YOUR COMPANIES'), findsNothing, reason: 'Close closes');
    expect(switched, isFalse, reason: 'closing switches nothing');
  });

  testWidgets('fits 360 dp at 200% text with no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await openAccountMenu(tester, onAddCompany: () {});

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text');
    await tester.scrollUntilVisible(find.text('Close'), 100,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Close'), findsOneWidget,
        reason: 'the menu scrolls rather than cutting off Close');
  });
}
