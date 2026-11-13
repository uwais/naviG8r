// The copy row's states from spec/components.md: default, copied for 3 s, loading, empty,
// not yet available, and clipboard blocked, with what is copied and what is announced.
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/ui/nv_copy_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mountRow(WidgetTester tester, NvCopyRow row) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: DriverTheme.theme(),
    home:
        Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: row)),
  ));
}

/// Records what reaches the clipboard; [blocked] makes the platform refuse the copy.
List<String> watchClipboard(WidgetTester tester, {bool blocked = false}) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      if (blocked) throw PlatformException(code: 'blocked');
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// Records what a screen reader is told, as (words, assertiveness index).
List<(String, int)> watchAnnouncements(WidgetTester tester) {
  final announced = <(String, int)>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (message) async {
    if ((message as Map)['type'] != 'announce') return null;
    final data = message['data'] as Map;
    announced
        .add((data['message'] as String, (data['assertiveness'] as int?) ?? 0));
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, null));
  return announced;
}

const truckRow = NvCopyRow(
    label: 'Truck number',
    value: 'KA01AB1234',
    portalField: 'Portal field: Vehicle No. (Part B)');

void main() {
  testWidgets(
      'shows the label, the value and the portal field with a labelled Copy',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await mountRow(tester, truckRow);

    expect(find.text('Truck number'), findsOneWidget,
        reason: 'the row says what the value is');
    expect(find.text('KA01AB1234'), findsOneWidget,
        reason: 'the value to copy is shown');
    expect(find.text('Portal field: Vehicle No. (Part B)'), findsOneWidget,
        reason: 'testers could not tell where each value goes on the portal');
    expect(
        find.bySemanticsLabel('Copy truck number KA01AB1234'), findsOneWidget,
        reason:
            'accessibility.md: copy buttons are labelled with what they copy');
    expect(tester.getSize(find.byType(OutlinedButton)).height,
        greaterThanOrEqualTo(48),
        reason: 'tap targets are at least 48 dp');
    semantics.dispose();
  });

  testWidgets(
      'Copy copies "KA01AB1234" with no spaces, announces "Truck number copied" and says Copied for 3 s',
      (tester) async {
    final copied = watchClipboard(tester);
    final announced = watchAnnouncements(tester);
    await mountRow(
        tester,
        const NvCopyRow(
            label: 'Truck number',
            value: 'KA01 AB 1234',
            portalField: 'Portal field: Vehicle No. (Part B)'));

    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, ['KA01AB1234'],
        reason: 'the value is copied without the spaces it is shown with');
    expect(announced.map((a) => a.$1), ['Truck number copied.'],
        reason: 'accessibility.md: Copy announces "Truck number copied."');
    expect(find.text('Copied'), findsOneWidget,
        reason: 'the button confirms the copy in words');

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy'), findsOneWidget,
        reason: 'the button returns to Copy after 3 seconds');
    expect(find.text('Copied'), findsNothing,
        reason: 'the confirmation does not stay');
  });

  testWidgets('Copy takes keyboard focus and Enter copies', (tester) async {
    final copied = watchClipboard(tester);
    await mountRow(tester, truckRow);

    final copyFocus = Focus.of(tester.element(find.text('Copy')));
    copyFocus.requestFocus();
    await tester.pump();
    expect(copyFocus.hasFocus, isTrue,
        reason: 'components PNG: Copy shows a focus state for keyboards');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(copied, ['KA01AB1234'], reason: 'Enter on the focused Copy copies');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
      'a grouped bill number is shown in groups and copied without spaces',
      (tester) async {
    final copied = watchClipboard(tester);
    await mountRow(tester,
        const NvCopyRow(label: 'E-way bill number', value: '3412 0098 7654'));

    expect(find.text('3412 0098 7654'), findsOneWidget,
        reason: 'copy.md: bill numbers are shown as 3412 0098 7654');
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, ['341200987654'],
        reason: 'copy.md: bill numbers are copied without spaces');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('while loading it shows the guidance and Copy cannot be pressed',
      (tester) async {
    await mountRow(
        tester,
        const NvCopyRow(
            label: "Carrier's transporter ID",
            guidance: "Loading from Ravi Roadways' profile",
            state: NvCopyRowState.loading));

    expect(find.text("Loading from Ravi Roadways' profile"), findsOneWidget,
        reason: 'loading says where the value comes from');
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
        reason: 'nothing can be copied before the value arrives');
  });

  testWidgets('empty shows why there is no value, the guidance, and no Copy',
      (tester) async {
    await mountRow(
        tester,
        const NvCopyRow(
            label: "Carrier's transporter ID",
            noValueWords: 'Ravi Roadways has not added one.',
            guidance:
                'Leave Transporter ID empty. Only you, the bill\'s maker, can then change the truck.',
            state: NvCopyRowState.empty));

    expect(find.text('Ravi Roadways has not added one.'), findsOneWidget,
        reason:
            'copy.md: an absent transporter ID is explained, not left blank');
    expect(
        find.text(
            'Leave Transporter ID empty. Only you, the bill\'s maker, can then change the truck.'),
        findsOneWidget,
        reason: 'the shipper is told what to do instead');
    expect(find.text('Copy'), findsNothing, reason: 'there is nothing to copy');
  });

  testWidgets('not yet available shows the reason and a disabled Copy',
      (tester) async {
    await mountRow(
        tester,
        const NvCopyRow(
            label: 'Truck number',
            noValueWords: 'Not chosen yet',
            guidance: 'Shown once the carrier accepts and names the truck.',
            state: NvCopyRowState.notYet));

    expect(find.text('Not chosen yet'), findsOneWidget,
        reason: 'the row says the truck is not chosen yet');
    expect(find.text('Shown once the carrier accepts and names the truck.'),
        findsOneWidget,
        reason: 'the row says when the value will appear');
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
        reason: 'Copy is disabled until there is a truck');
  });

  testWidgets(
      'a blocked clipboard shows and assertively announces how to copy by hand',
      (tester) async {
    watchClipboard(tester, blocked: true);
    final announced = watchAnnouncements(tester);
    await mountRow(tester, truckRow);

    await tester.tap(find.text('Copy'));
    await tester.pump();
    const words = 'Could not copy. Press and hold the number to copy it.';
    expect(find.text(words), findsOneWidget,
        reason: 'accessibility.md: a failed copy says how to copy by hand');
    expect(announced, [(words, Assertiveness.assertive.index)],
        reason: 'accessibility.md: the failed copy is announced assertively');
    expect(find.byType(SelectableText), findsOneWidget,
        reason: 'press and hold works because the value is selectable');
    expect(find.text('Copied'), findsNothing,
        reason: 'a failed copy never says Copied');
  });

  testWidgets('fits 360 dp at 200% text with no overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await mountRow(tester, truckRow);

    expect(tester.takeException(), isNull,
        reason: 'accessibility.md: works at 200% text');
    expect(find.text('Portal field: Vehicle No. (Part B)'), findsOneWidget,
        reason: 'the portal field wraps instead of disappearing');
  });
}
