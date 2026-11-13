import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_message.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> expectMessage(WidgetTester tester,
      {required NvMessage message, required Color tint}) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: message))));

    expect(find.text(message.text), findsOneWidget,
        reason: 'the message says what happened in words');
    final box = tester.widget<Container>(find.descendant(
        of: find.byType(NvMessage), matching: find.byType(Container)));
    expect((box.decoration! as BoxDecoration).color, tint,
        reason: 'nv.css .msg: each tone has its own tint');
    expect(tester.getSemantics(find.text(message.text)),
        containsSemantics(label: message.text, isLiveRegion: true),
        reason: 'components.md: NvMessage is a live region, so it is read out');
    handle.dispose();
  }

  testWidgets('info', (tester) async {
    await expectMessage(tester,
        message: const NvMessage(
            'Next, you choose how to pay on the payment provider\'s screen.',
            tone: NvMessageTone.info),
        tint: NvColors.infoTint);
  });

  testWidgets('attention', (tester) async {
    await expectMessage(tester,
        message: const NvMessage(
            'Add it on the portal before these goods move.',
            tone: NvMessageTone.attention),
        tint: NvColors.attentionTint);
  });

  testWidgets('good, with a tick', (tester) async {
    await expectMessage(tester,
        message: const NvMessage(
            'E-way bill saved. Nothing more for you to do until delivery.',
            tone: NvMessageTone.good),
        tint: NvColors.goodTint);
    expect(find.byIcon(Icons.check), findsOneWidget,
        reason: 'cp-copy: a good message carries a tick as well as words');
  });

  testWidgets('problem', (tester) async {
    await expectMessage(tester,
        message: const NvMessage(
            'Could not accept. Check your connection and try again.',
            tone: NvMessageTone.problem),
        tint: NvColors.problemTint);
  });

  testWidgets('a title line is bold and read with the message', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
        theme: DriverTheme.theme(),
        home: const Scaffold(
            body: NvMessage('Guindy · Sharma Textiles · 14:20 IST',
                tone: NvMessageTone.good, title: 'Delivery confirmed'))));

    expect(
        tester.widget<Text>(find.text('Delivery confirmed')).style!.fontWeight,
        FontWeight.w700,
        reason: 'dr-done: the title line is bold');
    expect(
        tester.getSemantics(find.byType(NvMessage)),
        containsSemantics(
            label: 'Delivery confirmed\nGuindy · Sharma Textiles · 14:20 IST'),
        reason: 'title and message are announced together as one region');
    handle.dispose();
  });
}
