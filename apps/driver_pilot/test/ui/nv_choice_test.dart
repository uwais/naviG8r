import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_choice.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const truckSizes = [
    NvChoice('SMALL', 'Small'),
    NvChoice('MEDIUM', 'Medium'),
    NvChoice('LARGE', 'Large'),
  ];
  const trucks = [
    NvChoice('KA01AB1234', 'KA01AB1234',
        caption: 'Medium truck', labelIsIdentifier: true),
    NvChoice('KA05CD5678', 'KA05CD5678',
        caption: 'Large truck', labelIsIdentifier: true),
  ];

  // Holds the chosen value the way a screen would, so a tap shows as chosen.
  Future<List<String>> showChoices(WidgetTester tester,
      Widget Function(String? chosen, ValueChanged<String>? choose) build,
      {bool enabled = true}) async {
    final chosenValues = <String>[];
    String? chosen;
    await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder: (context, setState) => build(
                chosen,
                enabled
                    ? (value) => setState(() {
                          chosen = value;
                          chosenValues.add(value);
                        })
                    : null),
          ),
        ),
      ),
    ));
    return chosenValues;
  }

  ChoiceChip chip(WidgetTester tester, String label) =>
      tester.widget<ChoiceChip>(find.ancestor(
          of: find.text(label), matching: find.byType(ChoiceChip)));

  void useKeyboardFocus() {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic);
  }

  group('NvChoiceChips', () {
    Widget truckSizeChips(String? chosen, ValueChanged<String>? choose) =>
        NvChoiceChips<String>(
            label: 'Truck size',
            options: truckSizes,
            selected: chosen,
            onChanged: choose,
            disabledReason: 'Choose the trip first.');

    testWidgets('none selected: every option shows, none is chosen',
        (tester) async {
      final handle = tester.ensureSemantics();
      await showChoices(tester, truckSizeChips);

      expect(find.text('Truck size'), findsOneWidget,
          reason: 'cp-field: the choice has a visible label');
      for (final size in ['Small', 'Medium', 'Large']) {
        expect(find.text(size), findsOneWidget,
            reason: 'cp-field: sizes are words, never SMALL|MEDIUM|LARGE');
        expect(chip(tester, size).selected, isFalse,
            reason:
                'decisions.md: never preselect a choice the user has not made');
        expect(tester.getSize(find.byType(ChoiceChip).first).height,
            greaterThanOrEqualTo(48),
            reason: 'accessibility.md: every target is at least 48 dp');
      }
      expect(find.text('SMALL'), findsNothing,
          reason: 'no raw codes in the UI');
      handle.dispose();
    });

    testWidgets('selected: a tap chooses that option only, navy fill',
        (tester) async {
      final handle = tester.ensureSemantics();
      final chosen = await showChoices(tester, truckSizeChips);
      await tester.tap(find.text('Medium'));
      await tester.pump();

      expect(chosen, ['MEDIUM'],
          reason: 'the screen receives the value, not the words');
      expect(chip(tester, 'Medium').selected, isTrue,
          reason: 'cp-field: the chosen chip shows as chosen');
      expect(chip(tester, 'Small').selected, isFalse,
          reason: 'only one size is chosen at a time');
      expect(chip(tester, 'Medium').selectedColor, NvColors.navy,
          reason: 'cp-field: the chosen chip is navy');
      expect(tester.getSemantics(find.text('Medium')),
          containsSemantics(label: 'Medium', isSelected: true),
          reason: 'a screen reader hears which size is chosen');
      handle.dispose();
    });

    testWidgets('focus: keyboard focus reaches the first chip', (tester) async {
      final handle = tester.ensureSemantics();
      useKeyboardFocus();
      await showChoices(tester, truckSizeChips);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(tester.getSemantics(find.text('Small')),
          containsSemantics(label: 'Small', isFocused: true),
          reason: 'accessibility.md: every choice is reachable by keyboard');
      handle.dispose();
    });

    testWidgets('disabled: says why, and a tap chooses nothing',
        (tester) async {
      final handle = tester.ensureSemantics();
      final chosen = await showChoices(tester, truckSizeChips, enabled: false);
      await tester.tap(find.text('Large'));
      await tester.pump();

      expect(find.text('Choose the trip first.'), findsOneWidget,
          reason: 'a disabled choice always says why');
      expect(chosen, isEmpty, reason: 'a disabled chip cannot be chosen');
      expect(tester.getSemantics(find.text('Large')),
          containsSemantics(isEnabled: false),
          reason: 'a screen reader hears that the choice is not available');
      handle.dispose();
    });
  });

  group('NvChoiceRows', () {
    Widget truckRows(String? chosen, ValueChanged<String>? choose) =>
        NvChoiceRows<String>(
            options: trucks,
            selected: chosen,
            onChanged: choose,
            disabledReason: 'Add a truck to your company first.');

    List<Radio<String>> radios(WidgetTester tester) =>
        tester.widgetList<Radio<String>>(find.byType(Radio<String>)).toList();

    testWidgets('none selected: NvChoiceRows starts with nothing selected',
        (tester) async {
      final handle = tester.ensureSemantics();
      await showChoices(tester, truckRows);

      expect(find.text('KA01AB1234'), findsOneWidget,
          reason: 'cp-sheet: each truck is its own row');
      expect(find.text('Medium truck'), findsOneWidget,
          reason: 'cp-sheet: the row says what the truck is');
      expect(radios(tester).where((radio) => radio.value == radio.groupValue),
          isEmpty,
          reason: 'decisions.md: no truck preselected, even the only one');
      expect(tester.getSize(find.byType(RadioListTile<String>).first).height,
          greaterThanOrEqualTo(48),
          reason: 'accessibility.md: every target is at least 48 dp');
      expect(
          tester.getSemantics(find.text('KA01AB1234')),
          containsSemantics(
              label: 'KA01AB1234\nMedium truck',
              isInMutuallyExclusiveGroup: true,
              isChecked: false),
          reason: 'a screen reader hears a radio row that is not chosen');
      handle.dispose();
    });

    testWidgets('selected: a tap chooses that row, with a 2 dp navy border',
        (tester) async {
      final handle = tester.ensureSemantics();
      final chosen = await showChoices(tester, truckRows);
      await tester.tap(find.text('KA05CD5678'));
      await tester.pump();

      expect(chosen, ['KA05CD5678'], reason: 'the screen receives the value');
      expect(tester.getSemantics(find.text('KA05CD5678')),
          containsSemantics(isChecked: true),
          reason: 'a screen reader hears which row is chosen');
      expect(tester.getSemantics(find.text('KA01AB1234')),
          containsSemantics(isChecked: false),
          reason: 'only one row is chosen at a time');
      final chosenTile = tester.widget<RadioListTile<String>>(find.ancestor(
          of: find.text('KA05CD5678'),
          matching: find.byType(RadioListTile<String>)));
      expect((chosenTile.shape! as RoundedRectangleBorder).side,
          const BorderSide(color: NvColors.navy, width: 2),
          reason: 'nv.css .choice.on: the chosen row has a 2 dp navy border');
      handle.dispose();
    });

    testWidgets('focus: keyboard focus reaches the first row', (tester) async {
      final handle = tester.ensureSemantics();
      useKeyboardFocus();
      await showChoices(tester, truckRows);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(tester.getSemantics(find.text('KA01AB1234')),
          containsSemantics(isFocused: true),
          reason: 'accessibility.md: focus moves to the choices in order');
      handle.dispose();
    });

    testWidgets('disabled: says why, and a tap chooses nothing',
        (tester) async {
      final handle = tester.ensureSemantics();
      final chosen = await showChoices(tester, truckRows, enabled: false);
      await tester.tap(find.text('KA01AB1234'));
      await tester.pump();

      expect(find.text('Add a truck to your company first.'), findsOneWidget,
          reason: 'a disabled choice always says why');
      expect(chosen, isEmpty, reason: 'a disabled row cannot be chosen');
      expect(tester.getSemantics(find.text('KA01AB1234')),
          containsSemantics(isEnabled: false),
          reason: 'a screen reader hears that the row is not available');
      handle.dispose();
    });
  });
}
