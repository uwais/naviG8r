// The list card's states from spec/components.md: default, needs you, unavailable (Full),
// loading, empty and error, and the rule that the whole card is its only tap target.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_button.dart';
import 'package:driver_pilot/ui/nv_list_card.dart';
import 'package:driver_pilot/ui/nv_status_label.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mountList(WidgetTester tester, List<Widget> children) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DriverTheme.theme(),
    home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: children)),
  ));
}

NvListCard laneCard(VoidCallback onOpen,
        {String status = 'Open', String roomLeft = '105 kg'}) =>
    NvListCard(
      title: 'Bengaluru to Chennai',
      status: Text(status),
      subtitle: 'Ravi Roadways · Medium truck',
      facts: [
        const NvFact('Dates', '18 – 19 Oct'),
        NvFact('Room left', roomLeft)
      ],
      onOpen: onOpen,
    );

void main() {
  testWidgets('shows the route, caption, facts as label over value, and status',
      (tester) async {
    await mountList(tester, [laneCard(() {})]);

    expect(find.text('Bengaluru to Chennai'), findsOneWidget,
        reason: 'the route is the card title');
    expect(find.text('Ravi Roadways · Medium truck'), findsOneWidget,
        reason: 'the caption names the carrier and truck size');
    expect(find.text('Room left'), findsOneWidget,
        reason: 'facts have a short label');
    expect(find.text('105 kg'), findsOneWidget,
        reason: 'facts show their value');
    expect(
        tester.getTopLeft(find.text('105 kg')).dy >
            tester.getTopLeft(find.text('Room left')).dy,
        isTrue,
        reason: 'spec/components.md: facts row is label over value');
    expect(find.text('Open'), findsOneWidget,
        reason: 'every card has its status in words');
  });

  testWidgets(
      'has exactly one tappable target, the whole card, with no buttons inside',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    await mountList(tester, [laneCard(() => opened++)]);

    expect(find.byType(ButtonStyleButton), findsNothing,
        reason:
            'no buttons inside, so a slip cannot start a trip or remove anything');
    expect(find.byType(InkWell), findsOneWidget,
        reason: 'the card is one tap target');
    final tappableNodes = <SemanticsNode>[];
    void collect(SemanticsNode node) {
      if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
        tappableNodes.add(node);
      }
      node.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(tester
        .renderObject(find.byType(MaterialApp))
        .owner!
        .semanticsOwner!
        .rootSemanticsNode!);
    expect(tappableNodes, hasLength(1),
        reason: 'a screen reader finds one tappable item per card');
    expect(tappableNodes.single.label, contains('Bengaluru to Chennai'),
        reason: 'the tappable item reads the whole card');

    await tester.tap(find.text('Ravi Roadways · Medium truck'));
    await tester.tap(find.text('105 kg'));
    expect(opened, 2, reason: 'tapping anywhere on the card opens it');
    semantics.dispose();
  });

  testWidgets('pressed shows the sunken highlight', (tester) async {
    await mountList(tester, [laneCard(() {})]);

    expect(tester.widget<InkWell>(find.byType(InkWell)).highlightColor,
        NvColors.sunken,
        reason: 'components PNG: a pressed card turns sunken');
  });

  testWidgets('keyboard focus reaches the card and Enter opens it',
      (tester) async {
    var opened = false;
    await mountList(tester, [laneCard(() => opened = true)]);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Bengaluru to Chennai'))).hasFocus,
        isTrue,
        reason: 'the card can be reached by keyboard');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, isTrue, reason: 'Enter opens the focused card');
  });

  testWidgets('needs you draws the navy border and the "Next:" line',
      (tester) async {
    await mountList(tester, [
      NvListCard(
        title: 'Bengaluru to Chennai',
        status: const Text('Needs you'),
        subtitle: '18 Oct · 80 kg · Ravi Roadways',
        next: 'you make the e-way bill.',
        needsYou: true,
        onOpen: () {},
      ),
    ]);

    expect(find.text('Next: you make the e-way bill.', findRichText: true),
        findsOneWidget,
        reason: 'the Next line says who acts');
    final shape = tester
        .widget<Material>(find
            .ancestor(of: find.byType(InkWell), matching: find.byType(Material))
            .first)
        .shape! as RoundedRectangleBorder;
    expect(shape.side.color, NvColors.navy,
        reason: 'spec/components.md: needs-you cards have the navy border');
  });

  testWidgets('a full lane still opens and says "Room left: None"',
      (tester) async {
    var opened = false;
    await mountList(tester,
        [laneCard(() => opened = true, status: 'Full', roomLeft: 'None')]);

    expect(find.text('Full'), findsOneWidget,
        reason: 'copy.md: a full lane is labelled Full');
    expect(find.text('None'), findsOneWidget,
        reason: 'copy.md: a full lane shows "Room left: None"');
    await tester.tap(find.text('Bengaluru to Chennai'));
    expect(opened, isTrue,
        reason: 'components PNG: unavailable cards still open');
  });

  testWidgets('the loading card is a placeholder hidden from screen readers',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountList(
        tester, [const NvListLoadingCard(), const Text('Loading lanes.')]);

    expect(find.text('Loading lanes.'), findsOneWidget,
        reason: 'the list says it is loading in words');
    expect(find.byType(InkWell), findsNothing,
        reason: 'a placeholder cannot be opened');
    expect(
        find.descendant(
            of: find.byType(NvListLoadingCard),
            matching: find.byType(ExcludeSemantics)),
        findsWidgets,
        reason: 'placeholder shapes are not read aloud');
    semantics.dispose();
  });

  testWidgets('empty shows its title and help', (tester) async {
    await mountList(tester, [
      const NvListEmpty(
          title: 'No lanes are open right now.',
          help: 'New lanes appear here when carriers publish them.'),
    ]);

    expect(find.text('No lanes are open right now.'), findsOneWidget,
        reason: 'copy.md: empty lanes title');
    expect(find.text('New lanes appear here when carriers publish them.'),
        findsOneWidget,
        reason: 'copy.md: empty lanes says what will happen');
  });

  testWidgets('error shows its words and Try again', (tester) async {
    var retried = false;
    await mountList(tester, [
      NvListError(
          title: 'Could not load lanes.',
          help: 'Check your connection, then try again.',
          onRetry: () => retried = true),
    ]);

    expect(find.text('Could not load lanes.'), findsOneWidget,
        reason: 'copy.md: the error says what failed');
    expect(find.text('Check your connection, then try again.'), findsOneWidget,
        reason: 'copy.md: the error says what to do');
    expect(find.widgetWithText(NvButton, 'Try again'), findsOneWidget,
        reason: 'Try again is the shared secondary button, like every other');
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue, reason: 'Try again reloads the list');
  });

  testWidgets('fits 360 dp at 200% text with no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await mountList(tester, [laneCard(() {})]);

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: cards grow, nothing truncates');
    expect(find.text('Room left'), findsOneWidget,
        reason: 'facts wrap instead of disappearing');
  });

  testWidgets(
      'at 200% text a long status drops under the title and stays on the card',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    const status = 'Waiting for payment';
    await mountList(tester, [
      NvListCard(
        title: 'Bengaluru to Chennai',
        status: const NvStatusLabel(status, tone: NvStatusTone.attention),
        onOpen: () {},
      ),
    ]);

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: 200% text on 360 dp, nothing overflows');
    final card = tester.getRect(find.byType(InkWell));
    final label = tester.getRect(find.byType(NvStatusLabel));
    expect(label.right <= card.right && label.left >= card.left, isTrue,
        reason: 'the status stays inside the card instead of running off it');
    expect(label.top >= tester.getRect(find.text('Bengaluru to Chennai')).bottom,
        isTrue,
        reason: 'a status that does not fit beside the title drops under it');
  });

  testWidgets('at normal text a short status sits beside the title',
      (tester) async {
    // The test font draws every letter as a square, so a short route is what fits beside a status.
    await mountList(tester, [
      NvListCard(
          title: 'Pune to Goa',
          status: const NvStatusLabel('Open', tone: NvStatusTone.info),
          onOpen: () {}),
    ]);

    final title = tester.getRect(find.text('Pune to Goa'));
    final label = tester.getRect(find.byType(NvStatusLabel));
    expect(label.top < title.bottom, isTrue,
        reason: 'mockups: the status is on the title line when it fits');
    expect(label.left > title.right, isTrue,
        reason: 'mockups: the status is at the right of the title');
  });
}
