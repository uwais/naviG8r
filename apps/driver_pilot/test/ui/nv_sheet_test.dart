// The bottom sheet's states from spec/components.md: nothing chosen, chosen, loading, error
// (stays open, choice kept), success (closes and announces) and empty.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The accept sheet as a screen would build it, with its state held outside [NvSheet].
class TruckSheetHarness extends StatefulWidget {
  const TruckSheetHarness(
      {this.accept,
      this.startLoading = false,
      this.trucks = const ['KA01AB1234', 'KA05CD9012'],
      super.key});

  /// Returns error words, or null when accepting worked.
  final Future<String?> Function()? accept;
  final bool startLoading;
  final List<String> trucks;

  @override
  State<TruckSheetHarness> createState() => _TruckSheetHarnessState();
}

class _TruckSheetHarnessState extends State<TruckSheetHarness> {
  String? chosen;
  String? error;
  late bool loading = widget.startLoading;

  Future<void> _accept() async {
    setState(() => loading = true);
    final failure = await widget.accept!();
    if (!mounted) return;
    if (failure == null) {
      closeNvSheetAfterSuccess(context,
          announcement:
              'Accepted with $chosen. Sharma Textiles can make the e-way bill now.',
          result: chosen);
      return;
    }
    setState(() {
      loading = false;
      error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.trucks.isEmpty) {
      return NvSheet(
        title: 'Which truck carries this trip?',
        message: 'You have no trucks yet. Add one to accept bookings.',
        primaryLabel: 'Add truck',
        onPrimary: () {},
      );
    }
    return NvSheet(
      title: 'Which truck carries this trip?',
      errorText: error,
      choices: [
        for (final truck in widget.trucks)
          RadioListTile<String>(
            value: truck,
            groupValue: chosen,
            title: Text(truck),
            onChanged: (value) => setState(() => chosen = value),
          ),
      ],
      primaryLabel:
          chosen == null ? 'Accept with this truck' : 'Accept with $chosen',
      onPrimary: chosen == null ? null : _accept,
      disabledReason: 'Choose a truck first.',
      loading: loading,
      loadingLabel: 'Accepting',
    );
  }
}

String? sheetResult;

Future<void> openSheet(WidgetTester tester, Widget sheet) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  sheetResult = null;
  await tester.pumpWidget(MaterialApp(
    theme: DriverTheme.theme(),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: OutlinedButton(
            onPressed: () async => sheetResult = await showNvSheet<String>(
                context: context, builder: (_) => sheet),
            child: const Text('Review booking'),
          ),
        ),
      ),
    ),
  ));
  // Opened from the keyboard, as a screen reader or switch user would, so the opener has focus.
  Focus.of(tester.element(find.text('Review booking'))).requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  // Not pumpAndSettle: the loading state's progress ring never settles.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

ButtonStyleButton buttonWithText(WidgetTester tester, String text) =>
    tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.text(text), matching: find.bySubtype<ButtonStyleButton>()));

void main() {
  testWidgets(
      'opened with nothing chosen: the primary is disabled with its reason',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openSheet(tester, const TruckSheetHarness());

    expect(find.text('Which truck carries this trip?'), findsOneWidget,
        reason: 'the title is a question');
    expect(
        tester
            .widgetList<RadioListTile<String>>(
                find.byType(RadioListTile<String>))
            .every((tile) => tile.groupValue == null),
        isTrue,
        reason: 'decisions.md: nothing preselected');
    expect(buttonWithText(tester, 'Accept with this truck').onPressed, isNull,
        reason: 'the primary waits for a choice');
    expect(find.text('Choose a truck first.'), findsOneWidget,
        reason: 'a disabled action always says why');
    expect(find.text('Cancel'), findsOneWidget, reason: 'a neutral way out');
    expect(tester.getSize(find.bySubtype<FilledButton>()).width, 360 - 2 * 16,
        reason: 'the primary spans the sheet inside the 16 dp gutters');
    expect(tester.getSize(find.bySubtype<FilledButton>()),
        tester.getSize(find.bySubtype<OutlinedButton>().last),
        reason:
            'spec/components.md: primary and Cancel are full width, equal size');
    expect(
        tester.getSemantics(find.text('Which truck carries this trip?')),
        matchesSemantics(
            label: 'Which truck carries this trip?',
            isHeader: true,
            namesRoute: true),
        reason: 'accessibility.md: the sheet title is the dialog name');
    semantics.dispose();
  });

  testWidgets('choosing a truck names it on the primary', (tester) async {
    await openSheet(tester, const TruckSheetHarness());

    await tester.tap(find.text('KA01AB1234'));
    await tester.pump();
    expect(find.text('Accept with KA01AB1234'), findsOneWidget,
        reason: 'copy.md: the primary names the chosen truck');
    expect(
        buttonWithText(tester, 'Accept with KA01AB1234').onPressed, isNotNull,
        reason: 'a choice enables the primary');
    expect(find.text('Choose a truck first.'), findsNothing,
        reason: 'the reason goes once the action is possible');
  });

  testWidgets('loading shows the loading words and holds every control',
      (tester) async {
    await openSheet(tester, const TruckSheetHarness(startLoading: true));

    expect(find.text('Accepting'), findsOneWidget,
        reason: 'loading keeps words on the button');
    expect(buttonWithText(tester, 'Cancel').onPressed, isNull,
        reason: 'Cancel waits while the action runs');
    expect(
        tester
            .widget<AbsorbPointer>(find
                .ancestor(
                    of: find.text('KA01AB1234'),
                    matching: find.byType(AbsorbPointer))
                .first)
            .absorbing,
        isTrue,
        reason: 'the choice cannot change mid-action');
  });

  testWidgets('an error keeps the sheet open with the choice kept',
      (tester) async {
    await openSheet(
        tester,
        TruckSheetHarness(
            accept: () async =>
                'Could not accept. Check your connection and try again.'));

    await tester.tap(find.text('KA01AB1234'));
    await tester.pump();
    await tester.tap(find.text('Accept with KA01AB1234'));
    await tester.pumpAndSettle();
    expect(find.text('Could not accept. Check your connection and try again.'),
        findsOneWidget,
        reason: 'copy.md: the failure is said in words');
    expect(find.text('Which truck carries this trip?'), findsOneWidget,
        reason: 'the sheet stays open on error');
    expect(find.text('Accept with KA01AB1234'), findsOneWidget,
        reason: 'the choice is kept after an error');
  });

  testWidgets('success closes the sheet, returns the choice and announces it',
      (tester) async {
    final announced = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility, (message) async {
      if ((message as Map)['type'] == 'announce') {
        announced.add((message['data'] as Map)['message'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility, null));
    await openSheet(tester, TruckSheetHarness(accept: () async => null));

    await tester.tap(find.text('KA01AB1234'));
    await tester.pump();
    await tester.tap(find.text('Accept with KA01AB1234'));
    await tester.pumpAndSettle();
    expect(find.text('Which truck carries this trip?'), findsNothing,
        reason: 'the sheet closes after the action works');
    expect(sheetResult, 'KA01AB1234',
        reason: 'the screen gets the choice back');
    expect(
        announced,
        [
          'Accepted with KA01AB1234. Sharma Textiles can make the e-way bill now.'
        ],
        reason: 'accessibility.md: the result is announced');
  });

  testWidgets('empty says why there is no choice and offers the way forward',
      (tester) async {
    await openSheet(tester, const TruckSheetHarness(trucks: []));

    expect(find.text('You have no trucks yet. Add one to accept bookings.'),
        findsOneWidget,
        reason: 'copy.md: the empty sheet says why');
    expect(find.text('Add truck'), findsOneWidget,
        reason: 'copy.md: the empty sheet offers Add truck');
    expect(find.text('Cancel'), findsOneWidget, reason: 'the way out stays');
  });

  testWidgets('Cancel closes the sheet and focus returns to the opener',
      (tester) async {
    await openSheet(tester, const TruckSheetHarness());
    final opener = Focus.of(tester.element(find.text('Review booking')));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Which truck carries this trip?'), findsNothing,
        reason: 'Cancel closes the sheet');
    expect(sheetResult, isNull, reason: 'Cancel chooses nothing');
    expect(opener.hasFocus, isTrue,
        reason: 'accessibility.md: focus returns to the button that opened it');
  });

  testWidgets('fits 360 dp at 200% text with no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await openSheet(tester, const TruckSheetHarness());

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text');
    await tester.scrollUntilVisible(find.text('Cancel'), 100,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Cancel'), findsOneWidget,
        reason: 'the sheet scrolls rather than cutting off Cancel');
  });
}
