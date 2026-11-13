import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_status_label.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> showLabel(WidgetTester tester, NvStatusLabel label) =>
      tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: Scaffold(body: Center(child: label))));

  Future<void> expectStatus(WidgetTester tester,
      {required String word,
      required NvStatusTone tone,
      required Color tint,
      required Color wordColour}) async {
    final handle = tester.ensureSemantics();
    await showLabel(tester, NvStatusLabel(word, tone: tone));

    expect(find.text(word), findsOneWidget,
        reason: 'every status is a word, never colour alone');
    final box = tester.widget<Container>(find.descendant(
        of: find.byType(NvStatusLabel), matching: find.byType(Container)));
    expect((box.decoration! as BoxDecoration).color, tint,
        reason: 'cp-status: $tone sits on its own tint');
    expect(tester.widget<Text>(find.text(word)).style!.color, wordColour,
        reason: 'cp-status: the word takes the tone\'s colour');
    expect(tester.getSemantics(find.text(word)),
        containsSemantics(label: word, isButton: false, hasTapAction: false),
        reason: 'status labels are not tappable');
    handle.dispose();
  }

  testWidgets('attention: "Waiting for carrier" on the attention tint',
      (tester) async {
    await expectStatus(tester,
        word: 'Waiting for carrier',
        tone: NvStatusTone.attention,
        tint: NvColors.attentionTint,
        wordColour: NvColors.attention);
  });

  testWidgets('info: "In transit" on the info tint', (tester) async {
    await expectStatus(tester,
        word: 'In transit',
        tone: NvStatusTone.info,
        tint: NvColors.infoTint,
        wordColour: NvColors.navy);
  });

  testWidgets('good: "Delivered" on the good tint', (tester) async {
    await expectStatus(tester,
        word: 'Delivered',
        tone: NvStatusTone.good,
        tint: NvColors.goodTint,
        wordColour: NvColors.good);
  });

  testWidgets('problem: "E-way bill needs a fix" on the problem tint',
      (tester) async {
    await expectStatus(tester,
        word: 'E-way bill needs a fix',
        tone: NvStatusTone.problem,
        tint: NvColors.problemTint,
        wordColour: NvColors.problem);
  });

  testWidgets('ended: "Cancelled" is ink on sunken, no new colour',
      (tester) async {
    await expectStatus(tester,
        word: 'Cancelled',
        tone: NvStatusTone.ended,
        tint: NvColors.sunken,
        wordColour: NvColors.ink);
  });

  testWidgets(
      'a long status wraps at 360 dp and 200% text instead of overflowing',
      (tester) async {
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
                child: NvStatusLabel('Waiting for you to accept',
                    tone: NvStatusTone.attention))),
      ),
    ));
    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text, nothing overflows');
    expect(find.text('Waiting for you to accept'), findsOneWidget,
        reason: 'the whole word stays readable when it wraps');
  });
}
