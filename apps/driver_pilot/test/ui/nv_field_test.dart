import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showField(WidgetTester tester, NvField field) =>
      tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: Scaffold(
              body: Padding(padding: const EdgeInsets.all(16), child: field))));

  SemanticsNode fieldSemantics(WidgetTester tester) =>
      tester.getSemantics(find.byType(TextField));

  testWidgets(
      'default with help: label above, help below, hint and unit inside',
      (tester) async {
    final handle = tester.ensureSemantics();
    await showField(
        tester,
        const NvField(
            label: 'Weight',
            hint: 'For example 80',
            unit: 'kg',
            help: 'Up to 105 kg on this lane.'));

    expect(find.text('Weight'), findsOneWidget,
        reason: 'cp-field: the label is always visible');
    expect(tester.getBottomLeft(find.text('Weight')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(TextField)).dy),
        reason:
            'cp-field: the label sits above the field, not floating inside');
    expect(find.text('Up to 105 kg on this lane.'), findsOneWidget,
        reason: 'cp-field: help under the field says the format');
    expect(find.text('For example 80'), findsOneWidget,
        reason: 'cp-field: the empty field shows an example');
    expect(find.text('kg'), findsOneWidget,
        reason: 'cp-field: the unit shows at the end even when empty');
    expect(
        fieldSemantics(tester),
        containsSemantics(
            label: 'Weight\nFor example 80\nkg\nUp to 105 kg on this lane.',
            isTextField: true,
            isEnabled: true),
        reason: 'a screen reader hears the label and help with the field');
    handle.dispose();
  });

  testWidgets('focus: the border turns navy and 2 dp, label stays put',
      (tester) async {
    final handle = tester.ensureSemantics();
    await showField(tester, const NvField(label: 'Weight', unit: 'kg'));
    final labelTop = tester.getTopLeft(find.text('Weight'));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(fieldSemantics(tester), containsSemantics(isFocused: true),
        reason: 'tapping the field focuses it');
    expect(tester.getTopLeft(find.text('Weight')), labelTop,
        reason: 'cp-field: the label does not move or float on focus');
    final decorator =
        tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decorator.isFocused, isTrue,
        reason: 'the focused border from the theme applies');
    expect(
        Theme.of(tester.element(find.byType(TextField)))
            .inputDecorationTheme
            .focusedBorder!
            .borderSide,
        const BorderSide(color: NvColors.focus, width: 2),
        reason: 'cp-field: focus is a 2 dp navy border');
    handle.dispose();
  });

  testWidgets('filled: the typed value shows', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await showField(
        tester, NvField(label: 'Invoice number', controller: controller));
    await tester.enterText(find.byType(TextField), 'ST/2026/0418');
    await tester.pump();

    expect(find.text('ST/2026/0418'), findsOneWidget,
        reason: 'cp-field: a filled field shows its value');
    expect(controller.text, 'ST/2026/0418',
        reason: 'the value reaches the screen that owns the field');
  });

  testWidgets('optional: the label says "(optional)"', (tester) async {
    final handle = tester.ensureSemantics();
    await showField(
        tester,
        const NvField(
            label: 'Transporter ID',
            optional: true,
            hint: '15 characters',
            help: 'Your GSTIN, or a TRANSIN if you have no GST registration.'));

    expect(find.text('Transporter ID (optional)'), findsOneWidget,
        reason: 'cp-field: optional fields say so in the label');
    expect(fieldSemantics(tester).getSemanticsData().label,
        startsWith('Transporter ID (optional)'),
        reason: 'a screen reader hears that the field is optional');
    handle.dispose();
  });

  testWidgets('error: replaces the help, says what is wrong, red border',
      (tester) async {
    final handle = tester.ensureSemantics();
    await showField(
        tester,
        const NvField(
            label: 'E-way bill number',
            identifier: true,
            help: '12 digits, at the top of the bill.',
            errorText: 'This has 11 digits. An e-way bill number has 12.'));

    expect(find.text('This has 11 digits. An e-way bill number has 12.'),
        findsOneWidget,
        reason: 'copy.md: the error says what is wrong and how to fix it');
    expect(find.text('12 digits, at the top of the bill.'), findsNothing,
        reason: 'components.md: the error replaces the help');
    expect(find.byIcon(Icons.error_outline), findsOneWidget,
        reason: 'cp-field: the error has a mark, not colour alone');
    final decorator =
        tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decorator.decoration.error, isNotNull,
        reason: 'the theme error border (problem red) applies');
    expect(fieldSemantics(tester).getSemanticsData().label,
        contains('This has 11 digits. An e-way bill number has 12.'),
        reason: 'the error is read with the field, like aria-describedby');
    handle.dispose();
  });

  testWidgets('disabled with reason: cannot be typed in, reason replaces help',
      (tester) async {
    final handle = tester.ensureSemantics();
    await showField(
        tester,
        const NvField(
            label: 'Truck number',
            hint: 'Not chosen yet',
            help: 'Portal field: Vehicle No.',
            disabledReason: 'The carrier names the truck when they accept.'));

    expect(find.text('The carrier names the truck when they accept.'),
        findsOneWidget,
        reason: 'cp-field: a disabled field says why');
    expect(find.text('Portal field: Vehicle No.'), findsNothing,
        reason: 'the reason takes the help line');
    expect(find.text('Not chosen yet'), findsOneWidget,
        reason: 'cp-field: the disabled field says it is empty in words');
    expect(fieldSemantics(tester), containsSemantics(isEnabled: false),
        reason: 'a screen reader hears that the field is not available');
    final decorator =
        tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decorator.decoration.fillColor, NvColors.sunken,
        reason: 'cp-field: disabled fields are sunken');
    handle.dispose();
  });

  testWidgets('read-only: value to copy, sunken, no border', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController(text: '33AAACS7781L1ZQ');
    addTearDown(controller.dispose);
    await showField(
        tester,
        NvField(
            label: 'Your GSTIN',
            controller: controller,
            readOnly: true,
            identifier: true,
            help: 'Change it in your company details.'));

    expect(find.text('33AAACS7781L1ZQ'), findsOneWidget,
        reason: 'cp-field: a read-only field shows its value');
    expect(find.text('Change it in your company details.'), findsOneWidget,
        reason: 'cp-field: read-only help says where to change it');
    expect(fieldSemantics(tester), containsSemantics(isReadOnly: true),
        reason: 'a screen reader hears that the value cannot be edited here');
    final decorator =
        tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decorator.decoration.fillColor, NvColors.sunken,
        reason: 'cp-field: read-only fields are sunken');
    expect(decorator.decoration.enabledBorder!.borderSide, BorderSide.none,
        reason: 'cp-field: read-only fields have no border');
    expect(
        tester.widget<EditableText>(find.byType(EditableText)).style.fontFamily,
        'monospace',
        reason: 'copy.md: IDs are set in the mono face');
    handle.dispose();
  });

  testWidgets('loading: shows a ring and what it is doing', (tester) async {
    await showField(
        tester,
        NvField(
            label: 'Pickup',
            controller: TextEditingController(text: 'Bommasandra'),
            loadingLabel: 'Finding places'));

    expect(find.text('Finding places'), findsOneWidget,
        reason: 'cp-field: loading says what it is doing in words');
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'cp-field: loading shows a progress ring');
  });

  testWidgets('success: the saved line replaces the help in green',
      (tester) async {
    await showField(
        tester,
        NvField(
            label: 'Transporter ID',
            controller: TextEditingController(text: '29ABCDE1234F1Z5'),
            help: 'Your GSTIN, or a TRANSIN if you have no GST registration.',
            savedMessage: 'Saved. Shippers see it on their next e-way bill.'));

    expect(find.text('Saved. Shippers see it on their next e-way bill.'),
        findsOneWidget,
        reason: 'cp-field: saving confirms inline under the field');
    expect(
        find.text('Your GSTIN, or a TRANSIN if you have no GST registration.'),
        findsNothing,
        reason: 'the saved line takes the help line');
    final decorator =
        tester.widget<InputDecorator>(find.byType(InputDecorator));
    expect(decorator.decoration.helperStyle!.color, NvColors.good,
        reason: 'cp-field: the saved line is good green');
  });

  testWidgets('long help wraps at 360 dp and 200% text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const MediaQuery(
        data: MediaQueryData(
            size: Size(360, 800), textScaler: TextScaler.linear(2)),
        child: Scaffold(
            body: Padding(
                padding: EdgeInsets.all(16),
                child: NvField(
                    label: 'Your GSTIN',
                    help:
                        'The GSTIN that made the bill. Not the carrier\'s transporter ID.'))),
      ),
    ));

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text, nothing overflows');
    expect(
        find.text(
            'The GSTIN that made the bill. Not the carrier\'s transporter ID.'),
        findsOneWidget,
        reason: 'help is never cut off');
  });
}
