// The header's states from spec/components.md: default, pressed, focus, long name, with
// Back, and the driver task title. One button opens the account menu; nothing else is in it.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_account_sheet.dart';
import 'package:driver_pilot/ui/nv_header.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

NvHeader companyHeader(
        {String company = 'Sharma Textiles',
        String person = 'Priya Raman',
        String role = 'Shipper',
        String? backLabel,
        VoidCallback? onBack}) =>
    NvHeader(
      company: company,
      person: person,
      role: role,
      phone: '+91 98450 12345',
      companies: const [
        NvCompany(id: 'org-sharma', name: 'Sharma Textiles', role: 'Shipper'),
      ],
      currentCompanyId: 'org-sharma',
      onSwitch: (_) async => null,
      onSignOut: () {},
      backLabel: backLabel,
      onBack: onBack,
    );

Future<void> mountHeader(WidgetTester tester, NvHeader header) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DriverTheme.theme(),
    home: Scaffold(appBar: header, body: const Text('Good morning')),
  ));
}

void main() {
  testWidgets(
      'default shows company, "Person · Role" and one button with the full label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountHeader(tester, companyHeader());

    expect(find.text('Sharma Textiles'), findsOneWidget,
        reason: 'copy.md: the company is the header title');
    expect(find.text('Priya Raman · Shipper'), findsOneWidget,
        reason: 'copy.md: person and role under the company');
    expect(
        find.bySemanticsLabel(
            'Sharma Textiles, Priya Raman, Shipper. Switch company or sign out'),
        findsOneWidget,
        reason:
            'spec/components.md: the button says whose account and what it does');
    expect(find.byType(InkWell), findsOneWidget,
        reason:
            'decisions.md: one header button replaces drop-down, refresh, sign-out and avatar');
    expect(find.byType(IconButton), findsNothing,
        reason: 'no refresh, sign-out or avatar icons in the header');
    expect(
        tester.getSize(find.byType(InkWell)).height, greaterThanOrEqualTo(48),
        reason: 'tap targets are at least 48 dp');
    semantics.dispose();
  });

  testWidgets('pressed shows the sunken highlight and opens the account menu',
      (tester) async {
    await mountHeader(tester, companyHeader());

    expect(tester.widget<InkWell>(find.byType(InkWell)).highlightColor,
        NvColors.sunken,
        reason: 'components PNG: a pressed header turns sunken');
    await tester.tap(find.text('Sharma Textiles'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('YOUR COMPANIES'), findsOneWidget,
        reason: 'the header opens the account menu');
    expect(find.text('+91 98450 12345'), findsOneWidget,
        reason: 'the menu gets the values the header was given');
  });

  testWidgets(
      'keyboard focus reaches the header button and Enter opens the menu',
      (tester) async {
    await mountHeader(tester, companyHeader());

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
        Focus.of(tester.element(find.text('Sharma Textiles'))).hasFocus, isTrue,
        reason:
            'accessibility.md: the header account button comes first in focus order');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('YOUR COMPANIES'), findsOneWidget,
        reason: 'Enter opens the account menu');
  });

  testWidgets('a long company name ends in "..." and is read in full',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountHeader(
        tester,
        companyHeader(
            company: 'Sri Venkateshwara Transport Corporation',
            person: 'Lakshmi Venkataraman',
            role: 'Owner'));

    expect(tester.takeException(), isNull,
        reason: 'a long name does not overflow');
    final title = tester
        .widget<Text>(find.text('Sri Venkateshwara Transport Corporation'));
    expect(title.overflow, TextOverflow.ellipsis,
        reason: 'accessibility.md: only the header truncates');
    expect(title.maxLines, 1, reason: 'the header stays one line per row');
    expect(
        find.bySemanticsLabel(
            'Sri Venkateshwara Transport Corporation, Lakshmi Venkataraman, Owner. Switch company or sign out'),
        findsOneWidget,
        reason: 'the full name is in the accessible label');
    semantics.dispose();
  });

  testWidgets('a detail screen shows Back with its label beside the company',
      (tester) async {
    var wentBack = false;
    await mountHeader(tester,
        companyHeader(backLabel: 'Shipments', onBack: () => wentBack = true));

    expect(find.text('Shipments'), findsOneWidget,
        reason: 'components PNG: Back names the screen it returns to');
    expect(find.text('Sharma Textiles'), findsOneWidget,
        reason: 'the company button stays on detail screens');
    await tester.tap(find.text('Shipments'));
    expect(wentBack, isTrue, reason: 'Back goes back');
    expect(tester.getSize(find.bySubtype<TextButton>()).height,
        greaterThanOrEqualTo(48),
        reason: 'Back is at least 48 dp tall');
  });

  testWidgets(
      'a driver task screen shows Back and the task name, with no account button',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var wentBack = false;
    await mountHeader(
        tester,
        NvHeader.task(
            backLabel: 'Trip',
            onBack: () => wentBack = true,
            taskTitle: 'E-way bills'));

    expect(find.text('E-way bills'), findsOneWidget,
        reason: 'components PNG: the driver task title');
    expect(tester.getSemantics(find.text('E-way bills')),
        matchesSemantics(label: 'E-way bills', isHeader: true),
        reason: 'the task name is a heading');
    expect(find.textContaining('Switch company'), findsNothing,
        reason: 'task screens have no account button');
    await tester.tap(find.text('Trip'));
    expect(wentBack, isTrue, reason: 'Back returns to the trip');
    semantics.dispose();
  });

  testWidgets(
      "the sign-in screens' bar is Back alone, with no title or account button",
      (tester) async {
    var wentBack = false;
    await mountHeader(tester,
        NvHeader.task(backLabel: 'Back', onBack: () => wentBack = true));

    expect(find.text('Back'), findsOneWidget,
        reason: 'c-signin: the signed-out bar holds only Back');
    expect(find.textContaining('Switch company'), findsNothing,
        reason: 'signed out there is no account to switch');
    await tester.tap(find.text('Back'));
    expect(wentBack, isTrue, reason: 'Back leaves the sign-in step');
  });

  testWidgets('fits 360 dp at 200% text with no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await mountHeader(
        tester, companyHeader(backLabel: 'Shipments', onBack: () {}));

    expect(tester.takeException(), isNull,
        reason:
            'accessibility.md: works at 200% text; the header truncates instead');
    expect(find.text('Sharma Textiles'), findsOneWidget,
        reason: 'the company is still shown');
  });
}
