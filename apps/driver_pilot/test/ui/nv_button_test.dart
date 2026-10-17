import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_button.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showButton(WidgetTester tester, NvButton button,
      {bool reduceMotion = false}) {
    return tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(body: Center(child: button)),
        ),
      ),
    ));
  }

  Material materialOf(WidgetTester tester) => tester.widget<Material>(find
      .descendant(of: find.byType(NvButton), matching: find.byType(Material))
      .first);

  BorderSide borderOf(WidgetTester tester) =>
      (materialOf(tester).shape! as OutlinedBorder).side;

  group('default', () {
    testWidgets('primary is navy with white words, 48 dp tall', (tester) async {
      final handle = tester.ensureSemantics();
      await showButton(tester, NvButton(label: 'Accept', onPressed: () {}));

      expect(find.text('Accept'), findsOneWidget,
          reason: 'cp-buttons: the label says the outcome');
      expect(materialOf(tester).color, NvColors.navy,
          reason: 'cp-buttons: primary is navy');
      expect(tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(48),
          reason: 'accessibility.md: every target is at least 48 dp');
      expect(
          tester.getSemantics(find.byType(FilledButton)),
          containsSemantics(
              label: 'Accept',
              isButton: true,
              isEnabled: true,
              hasTapAction: true),
          reason: 'a screen reader hears the label as an enabled button');
      handle.dispose();
    });

    testWidgets('secondary is white with a control border', (tester) async {
      await showButton(
          tester,
          NvButton(
              label: 'Decline',
              kind: NvButtonKind.secondary,
              onPressed: () {}));

      expect(find.text('Decline'), findsOneWidget,
          reason: 'cp-buttons: neutral decline words');
      expect(materialOf(tester).color, NvColors.card,
          reason: 'cp-buttons: secondary is white');
      expect(borderOf(tester).color, NvColors.controlBorder,
          reason: 'cp-buttons: secondary has the 3:1 control border');
    });

    testWidgets(
        'destructive is red words and border on white, never a red fill',
        (tester) async {
      await showButton(
          tester,
          NvButton(
              label: 'Remove truck',
              kind: NvButtonKind.destructive,
              onPressed: () {}));

      expect(find.text('Remove truck'), findsOneWidget,
          reason: 'cp-buttons: the destructive label names what is removed');
      expect(materialOf(tester).color, NvColors.card,
          reason: 'cp-buttons: destructive is outlined, not filled red');
      expect(borderOf(tester).color, NvColors.problem,
          reason: 'cp-buttons: destructive has the problem-colour border');
      expect(materialOf(tester).textStyle!.color, NvColors.problem,
          reason: 'cp-buttons: destructive words are the problem colour');
    });

    testWidgets('quiet is a text button that keeps 48 dp height',
        (tester) async {
      await showButton(
          tester,
          NvButton(
              label: 'Change number',
              kind: NvButtonKind.quiet,
              onPressed: () {}));

      expect(find.text('Change number'), findsOneWidget,
          reason: 'cp-buttons: quiet buttons still have words');
      expect(find.byType(TextButton), findsOneWidget,
          reason: 'cp-buttons: quiet is a text button');
      expect(tester.getSize(find.byType(TextButton)).height,
          greaterThanOrEqualTo(48),
          reason: 'cp-buttons: quiet buttons are still 48 dp tall');
    });

    testWidgets('a driver primary is 56 dp tall', (tester) async {
      await showButton(
          tester,
          NvButton(
              label: 'Confirm delivery', forDriver: true, onPressed: () {}));

      expect(tester.getSize(find.byType(FilledButton)).height,
          greaterThanOrEqualTo(56),
          reason: 'accessibility.md: 56 dp for driver primaries');
    });

    testWidgets('full width fills a 360 dp phone less its gutters',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: Scaffold(
              body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: NvButton(
                      label: 'Continue to payment',
                      fullWidth: true,
                      onPressed: () {})))));

      expect(tester.getSize(find.byType(FilledButton)).width, 328,
          reason: 'sheets and action bars use full-width primaries');
    });
  });

  testWidgets('pressed: primary darkens to navy-deep', (tester) async {
    await showButton(tester, NvButton(label: 'Accept', onPressed: () {}));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(FilledButton)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(materialOf(tester).color, NvColors.navyDeep,
        reason: 'cp-buttons: pressed primary is navy-deep');
    await gesture.up();
  });

  testWidgets('pressed: secondary turns sunken', (tester) async {
    await showButton(
        tester,
        NvButton(
            label: 'Decline', kind: NvButtonKind.secondary, onPressed: () {}));
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(OutlinedButton)));
    await tester.pump(const Duration(milliseconds: 200));

    expect(materialOf(tester).color, NvColors.sunken,
        reason: 'cp-buttons: pressed secondary is sunken');
    await gesture.up();
  });

  testWidgets('focus: a navy ring sits outside the button', (tester) async {
    final handle = tester.ensureSemantics();
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic);
    await showButton(
        tester,
        NvButton(
            label: 'Decline', kind: NvButtonKind.secondary, onPressed: () {}));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(borderOf(tester), NvButton.focusRing,
        reason:
            'accessibility.md: focus ring is navy, 2 dp, visible on every button');
    expect(tester.getSemantics(find.byType(OutlinedButton)),
        containsSemantics(label: 'Decline', isFocused: true),
        reason: 'keyboard focus reaches the button');
    handle.dispose();
  });

  testWidgets('disabled: shows its reason in words and cannot be pressed',
      (tester) async {
    final handle = tester.ensureSemantics();
    await showButton(
        tester,
        const NvButton(
            label: 'Accept with this truck',
            onPressed: null,
            disabledReason: 'Choose a truck first.'));

    expect(find.text('Choose a truck first.'), findsOneWidget,
        reason: 'cp-buttons: a disabled button always has its reason under it');
    expect(materialOf(tester).color, NvColors.sunken,
        reason: 'cp-buttons: disabled is sunken grey, not faded navy');
    expect(
        tester.getSemantics(find.byType(FilledButton)),
        containsSemantics(
            label: 'Accept with this truck', isButton: true, isEnabled: false),
        reason: 'a screen reader hears that the button is not available');
    handle.dispose();
  });

  testWidgets('loading: keeps its colour, shows the loading words and a ring',
      (tester) async {
    var presses = 0;
    await showButton(
        tester,
        NvButton(
            label: 'Get price',
            loadingLabel: 'Getting price',
            loading: true,
            onPressed: () => presses++));

    expect(find.text('Getting price'), findsOneWidget,
        reason: 'copy.md: Get price shows "Getting price" while loading');
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'components.md: loading adds an 18 dp progress ring');
    expect(tester.getSize(find.byType(CircularProgressIndicator)),
        const Size(18, 18),
        reason: 'components.md: the ring is 18 dp');
    expect(materialOf(tester).color, NvColors.navy,
        reason: 'cp-buttons: a loading primary stays navy, it is not disabled');
    await tester.tap(find.byType(FilledButton));
    expect(presses, 0, reason: 'a loading button cannot be pressed twice');
  });

  testWidgets('loading with reduce motion shows the words only',
      (tester) async {
    await showButton(
        tester,
        NvButton(
            label: 'Save truck',
            loadingLabel: 'Saving',
            loading: true,
            onPressed: () {}),
        reduceMotion: true);

    expect(find.text('Saving'), findsOneWidget,
        reason: 'the loading words remain without motion');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'accessibility.md: spinners respect reduce-motion');
  });

  testWidgets('success: primary turns green with a tick and the new words',
      (tester) async {
    await showButton(tester,
        NvButton(label: 'Save', successLabel: 'Saved', onPressed: () {}));

    expect(find.text('Saved'), findsOneWidget,
        reason: 'cp-buttons: success says what happened');
    expect(find.text('Save'), findsNothing,
        reason: 'the success words replace the label');
    expect(find.byIcon(Icons.check), findsOneWidget,
        reason: 'cp-buttons: success carries a tick, not colour alone');
    expect(materialOf(tester).color, NvColors.good,
        reason: 'cp-buttons: primary success is good green');
  });

  testWidgets('success: secondary gets a green border and words',
      (tester) async {
    await showButton(
        tester,
        NvButton(
            label: 'Copy',
            kind: NvButtonKind.secondary,
            successLabel: 'Copied',
            onPressed: () {}));

    expect(find.text('Copied'), findsOneWidget,
        reason: 'cp-buttons: secondary success reads "Copied"');
    expect(borderOf(tester).color, NvColors.good,
        reason: 'cp-buttons: secondary success has a green border');
  });

  testWidgets('a long label wraps at 360 dp and 200% text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(360, 800), textScaler: TextScaler.linear(2)),
        child: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(16),
                child: NvButton(
                    label: 'I have made it. Enter the details',
                    fullWidth: true,
                    onPressed: () {}))),
      ),
    ));

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text, nothing overflows');
    expect(find.text('I have made it. Enter the details'), findsOneWidget,
        reason: 'the whole label stays on the button');
  });
}
