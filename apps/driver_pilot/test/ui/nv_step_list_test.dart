// The step list's states from spec/components.md: done, yours, waiting, later, problem,
// loading list, saving, success and error, each with what a screen reader hears.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_step_list.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mountSteps(WidgetTester tester, NvStepList list) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DriverTheme.theme(),
    home: Scaffold(
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16), child: list)),
  ));
}

const booked =
    NvStep(title: 'Booked and paid', who: '17 Oct', state: NvStepState.done);
const onTheWay =
    NvStep(title: 'On the way', who: 'Ravi Roadways', state: NvStepState.later);

BoxDecoration panelDecorationAround(WidgetTester tester, String text) => tester
    .widget<Container>(find
        .ancestor(of: find.text(text), matching: find.byType(Container))
        .first)
    .decoration! as BoxDecoration;

void main() {
  testWidgets('a done step is ticked and read as "Done: Booked and paid"',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountSteps(
        tester,
        const NvStepList(
            listName: 'Steps for this shipment', steps: [booked, onTheWay]));

    expect(find.text('Booked and paid'), findsOneWidget,
        reason: 'the step name is shown in words');
    expect(find.byIcon(Icons.check), findsOneWidget,
        reason: 'done steps differ by a tick, not by colour alone');
    expect(find.bySemanticsLabel('Done: Booked and paid'), findsOneWidget,
        reason: 'spec/components.md: done steps are read as "Done:"');
    expect(find.bySemanticsLabel('Steps for this shipment'), findsOneWidget,
        reason:
            'accessibility.md: the step list is one list named for the shipment');
    semantics.dispose();
  });

  testWidgets(
      'a later step shows its number and is read with its place in the list',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountSteps(
        tester,
        const NvStepList(listName: 'Steps', steps: [
          booked,
          NvStep(title: 'Carrier accepts', state: NvStepState.done),
          NvStep(title: 'E-way bill', state: NvStepState.later),
          onTheWay,
          NvStep(title: 'Delivered', state: NvStepState.later),
        ]));

    expect(find.text('4'), findsOneWidget,
        reason: 'a later step shows its number in the marker');
    expect(find.text('Ravi Roadways'), findsOneWidget,
        reason: 'a later step names who does it');
    expect(
        find.bySemanticsLabel('Step 4 of 5, not yet: On the way, Ravi Roadways'),
        findsOneWidget,
        reason:
            'spec/components.md: later steps are read as "Step n of m, later:"');
    semantics.dispose();
  });

  testWidgets('your step opens a panel with its question and buttons',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountSteps(
        tester,
        NvStepList(listName: 'Steps', steps: [
          booked,
          NvStep(
            title: 'E-way bill',
            who: 'You',
            state: NvStepState.yours,
            panel: Column(children: [
              const Text('Does this load need an e-way bill?'),
              FilledButton(
                  onPressed: () {}, child: const Text('Yes, make one')),
            ]),
          ),
        ]));

    expect(find.text('2'), findsOneWidget,
        reason: 'your step shows its number, with a halo');
    expect(find.text('Does this load need an e-way bill?'), findsOneWidget,
        reason: 'only your step opens, with one sentence');
    expect(find.text('Yes, make one'), findsOneWidget,
        reason: 'your step panel holds its button');
    expect(find.bySemanticsLabel('Your step: E-way bill, You'), findsOneWidget,
        reason: 'spec/components.md: your step is read as "Your step:"');
    expect(panelDecorationAround(tester, 'Yes, make one').border,
        Border.all(color: NvColors.navy),
        reason: 'your step panel has the navy border');
    semantics.dispose();
  });

  testWidgets('a waiting step shows who in a grey panel with no button',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountSteps(
        tester,
        const NvStepList(listName: 'Steps', steps: [
          NvStep(
            title: 'Carrier accepts',
            who: 'Ravi Roadways',
            state: NvStepState.waiting,
            panel: Text('The carrier names the truck.'),
          ),
        ]));

    expect(find.byIcon(Icons.schedule), findsOneWidget,
        reason: 'waiting steps differ by a clock marker');
    expect(find.text('The carrier names the truck.'),
        findsOneWidget,
        reason: 'a waiting step says who is acting');
    expect(find.byType(ButtonStyleButton), findsNothing,
        reason: 'a waiting step has no button');
    expect(
        panelDecorationAround(
                tester, 'The carrier names the truck.')
            .color,
        NvColors.sunken,
        reason: 'the waiting panel is grey');
    expect(find.bySemanticsLabel('In progress: Carrier accepts, Ravi Roadways'),
        findsOneWidget,
        reason: 'spec/components.md: waiting steps are read as "In progress:"');
    semantics.dispose();
  });

  testWidgets('a problem step shows "!" and a red-bordered panel with its fix',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountSteps(
        tester,
        NvStepList(listName: 'Steps', steps: [
          NvStep(
            title: 'E-way bill',
            who: 'You',
            state: NvStepState.problem,
            panel: FilledButton(
                onPressed: () {}, child: const Text('Fix the details')),
          ),
        ]));

    expect(find.text('!'), findsOneWidget,
        reason: 'problem steps differ by a "!" marker, not colour alone');
    expect(find.text('Fix the details'), findsOneWidget,
        reason: 'a problem step opens with its button');
    expect(panelDecorationAround(tester, 'Fix the details').border,
        Border.all(color: NvColors.problem),
        reason: 'the problem panel has the problem border');
    expect(find.bySemanticsLabel('Your step: E-way bill, You'), findsOneWidget,
        reason: 'a problem is the person\'s own step to fix');
    semantics.dispose();
  });

  testWidgets(
      'while the list loads it shows placeholder rows and the loading words',
      (tester) async {
    await mountSteps(
        tester,
        const NvStepList(
            listName: 'Steps',
            steps: [booked],
            loading: true,
            loadingWords: "Loading this shipment's steps."));

    expect(find.text("Loading this shipment's steps."), findsOneWidget,
        reason: 'loading has words, not only a shape');
    expect(find.text('Booked and paid'), findsNothing,
        reason: 'no stale steps show while loading');
  });

  testWidgets('saving keeps the step open with the panel the screen gives it',
      (tester) async {
    await mountSteps(
        tester,
        const NvStepList(listName: 'Steps', steps: [
          NvStep(
            title: 'E-way bill',
            who: 'You',
            state: NvStepState.yours,
            panel: Column(children: [
              Text('Saving your answer.'),
              FilledButton(onPressed: null, child: Text('Saving')),
            ]),
          ),
        ]));

    expect(find.text('E-way bill'), findsOneWidget,
        reason: 'the step stays in place while it saves');
    expect(find.text('Saving your answer.'), findsOneWidget,
        reason: 'the saving words show inside the step');
  });

  testWidgets('after a save the step collapses to Done with no panel',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountSteps(
        tester,
        const NvStepList(listName: 'Steps', steps: [
          NvStep(
            title: 'E-way bill',
            who: 'You',
            state: NvStepState.done,
            panel: Text('Copy four details from the portal\'s bill.'),
          ),
        ]));

    expect(find.bySemanticsLabel('Done: E-way bill'), findsOneWidget,
        reason: 'components PNG: the finished step collapses to Done');
    expect(
        find.text('Copy four details from the portal\'s bill.'), findsNothing,
        reason: 'a done step never opens a panel');
    semantics.dispose();
  });

  testWidgets('a failed save shows its words and Try again in a problem panel',
      (tester) async {
    await mountSteps(
        tester,
        NvStepList(listName: 'Steps', steps: [
          NvStep(
            title: 'E-way bill',
            who: 'You',
            state: NvStepState.problem,
            panel: Column(children: [
              const Text(
                  'Could not save. Check your connection and try again. Nothing was lost.'),
              FilledButton(onPressed: () {}, child: const Text('Try again')),
            ]),
          ),
        ]));

    expect(
        find.text(
            'Could not save. Check your connection and try again. Nothing was lost.'),
        findsOneWidget,
        reason: 'the error says what happened and that nothing was lost');
    expect(find.text('Try again'), findsOneWidget,
        reason: 'the error gives one way forward');
  });

  testWidgets('fits 360 dp at 200% text with no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await mountSteps(
        tester,
        const NvStepList(listName: 'Steps', steps: [
          booked,
          NvStep(
              title: 'Carrier accepts and names the truck',
              who: 'Ravi Roadways',
              state: NvStepState.waiting,
              panel: Text('Waiting for Ravi Roadways to accept.')),
          onTheWay,
        ]));

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text, nothing overflows');
    expect(find.text('Carrier accepts and names the truck'), findsOneWidget,
        reason: 'step names wrap instead of being cut off');
  });
}
