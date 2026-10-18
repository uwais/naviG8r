// The carrier's transporter ID in the app (owner decision, 16 Oct 2026): optional at sign-up, and on Profile the
// owner edits it, a dispatcher reads it and a driver does not see it.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/transporter_id_section.dart';
import 'package:driver_pilot/ui/nv_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/carrier_fixtures.dart';
import 'support/mock_api.dart';

const transporterIdRule =
    'A transporter ID is 15 letters and digits, starting with two digits: your GSTIN, or the TRANSIN from the e-way bill portal. Leave it empty if you do not have one.';

Future<void> mountSection(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: Scaffold(body: ListView(children: const [TransporterIdSection()]))));
}

// The label sits above the field (NvField), so the field is found inside the labelled NvField.
Finder transporterIdField() => find.descendant(
    of: find.widgetWithText(NvField, 'Transporter ID'),
    matching: find.byType(TextField));

Future<void> tapChange(WidgetTester tester) async {
  await tester.tap(find.text('Change transporter ID'));
  // Two frames: one shows the field, the next moves the cursor into it.
  await tester.pump();
  await tester.pump();
}

bool transporterIdFieldHasCursor(WidgetTester tester) => tester
    .widget<EditableText>(find.descendant(
        of: transporterIdField(), matching: find.byType(EditableText)))
    .focusNode
    .hasFocus;

void main() {
  setUp(() {
    DriverSession.transporterId = '29ABCDE1234F1Z5';
    DriverSession.transporterIdLoaded = true;
  });
  tearDown(DriverSession.clearCarrierCache);

  group('Transporter ID on Profile', () {
    testWidgets('the owner sees it filled in, changes it and saves',
        (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      Object? sent;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        sent = request.data;
        return jsonResponse({
          'org': {...carrierOrganization, 'transporterId': '27AAAAA0000A1Z5'}
        });
      });
      await mountSection(tester);
      await tapChange(tester);
      expect(
          tester.widget<TextField>(transporterIdField()).controller!.text,
          '29ABCDE1234F1Z5');
      await tester.enterText(transporterIdField(), ' 27aaaaa0000a1z5 ');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(sent, {'transporterId': '27aaaaa0000a1z5'});
      expect(find.text('27AAAAA0000A1Z5'), findsOneWidget,
          reason: 'the saved form, as the server wrote it');
      expect(transporterIdField(), findsNothing,
          reason: 'a successful save closes the field');
      expect(find.text('Change transporter ID'), findsOneWidget);
      expect(DriverSession.transporterId, '27AAAAA0000A1Z5');
      expect(find.text('Transporter ID saved.'), findsOneWidget);
    });

    testWidgets('once saved, it shows as text with a Change button, and Cancel puts it back',
        (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      final sent = <Object?>[];
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        sent.add(request.data);
        return jsonResponse({'org': carrierOrganization});
      });
      await mountSection(tester);
      expect(transporterIdField(), findsNothing);
      expect(find.text('29ABCDE1234F1Z5'), findsOneWidget);
      expect(find.text('Save transporter ID'), findsNothing);
      await tapChange(tester);
      expect(transporterIdFieldHasCursor(tester), isTrue,
          reason: 'Change puts the cursor in the field');
      await tester.enterText(transporterIdField(), '12345');
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(sent, isEmpty);
      expect(transporterIdField(), findsNothing);
      expect(find.text('29ABCDE1234F1Z5'), findsOneWidget);
      expect(find.text('Change transporter ID'), findsOneWidget);
      await tapChange(tester);
      expect(tester.widget<TextField>(transporterIdField()).controller!.text,
          '29ABCDE1234F1Z5',
          reason: 'Cancel drops what was typed');
    });

    testWidgets('Cancel after a refusal leaves no refusal for the next Change',
        (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
            'error': 'invalid_transporter_id',
            'detail': transporterIdRule,
            'field': 'transporterId'
          }, 400));
      await mountSection(tester);
      await tapChange(tester);
      await tester.enterText(transporterIdField(), '12345');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(find.text(transporterIdRule), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tapChange(tester);
      expect(find.text(transporterIdRule), findsNothing);
    });

    testWidgets('an empty field clears it', (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      Object? sent;
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        sent = request.data;
        return jsonResponse({'org': carrierOrganization});
      });
      await mountSection(tester);
      await tapChange(tester);
      await tester.enterText(transporterIdField(), '');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(sent, {'transporterId': null});
      expect(DriverSession.transporterId, isNull);
      expect(find.text('No transporter ID is saved now.'), findsOneWidget);
      expect(transporterIdField(), findsOneWidget,
          reason: 'with none saved, the field stays open');
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets(
        'clearing the field after a refusal sends the clear, drops the old refusal and says none is saved',
        (tester) async {
      DriverSession.transporterId = null;
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      final sent = <Object?>[];
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        sent.add(request.data);
        final body = request.data;
        return body is Map && body['transporterId'] != null
            ? jsonResponse({
                'error': 'invalid_transporter_id',
                'detail': transporterIdRule,
                'field': 'transporterId'
              }, 400)
            : jsonResponse({'org': carrierOrganization});
      });
      await mountSection(tester);
      await tester.enterText(transporterIdField(), '12345');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(find.text(transporterIdRule), findsOneWidget);
      await tester.enterText(transporterIdField(), '');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(sent, [
        {'transporterId': '12345'},
        {'transporterId': null}
      ]);
      expect(find.text(transporterIdRule), findsNothing);
      expect(find.text('No transporter ID is saved now.'), findsOneWidget);
    });

    testWidgets(
        'a successful save replaces the message from the save before it',
        (tester) async {
      DriverSession.transporterId = null;
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        final body = request.data;
        return jsonResponse({
          'org': {
            ...carrierOrganization,
            if (body is Map && body['transporterId'] != null)
              'transporterId': '27AAAAA0000A1Z5'
          }
        });
      });
      await mountSection(tester);
      await tester.enterText(transporterIdField(), '27AAAAA0000A1Z5');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(find.text('Transporter ID saved.'), findsOneWidget);
      await tapChange(tester);
      await tester.enterText(transporterIdField(), '');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(find.text('Transporter ID saved.'), findsNothing,
          reason:
              'a successful save must clear it too, not only a refused one');
      expect(find.text('No transporter ID is saved now.'), findsOneWidget);
    });

    testWidgets(
        'a refused save clears the earlier "Transporter ID saved." message',
        (tester) async {
      DriverSession.transporterId = null;
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        final body = request.data;
        return body is Map && body['transporterId'] == '12345'
            ? jsonResponse({
                'error': 'invalid_transporter_id',
                'detail': transporterIdRule,
                'field': 'transporterId'
              }, 400)
            : jsonResponse({
                'org': {
                  ...carrierOrganization,
                  'transporterId': '27AAAAA0000A1Z5'
                }
              });
      });
      await mountSection(tester);
      await tester.enterText(transporterIdField(), '27AAAAA0000A1Z5');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(find.text('Transporter ID saved.'), findsOneWidget);
      await tapChange(tester);
      await tester.enterText(transporterIdField(), '12345');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(find.text('Transporter ID saved.'), findsNothing,
          reason:
              'a refused save must clear it too, not only a successful one');
      expect(find.text(transporterIdRule), findsOneWidget);
    });

    testWidgets(
        'a refused save during a refresh started elsewhere on Profile keeps the field and the typed ID',
        (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      api.dio.httpClientAdapter = MockApiAdapter(
          (request) => jsonResponse({'error': 'unavailable'}, 500));
      await mountSection(tester);
      await tapChange(tester);
      // What Save vehicle's refresh does first, before /v1/pilot/me answers.
      DriverSession.clearCarrierCache();
      await tester.enterText(transporterIdField(), '27aaaaa0000a1z5');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(transporterIdField(), findsOneWidget,
          reason: 'the section read its state when it opened');
      expect(
          tester.widget<TextField>(transporterIdField()).controller!.text,
          '27aaaaa0000a1z5');
      expect(find.textContaining('Could not load'), findsNothing);
    });

    testWidgets(
        'a refresh started elsewhere on Profile does not swap the field out mid-edit',
        (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
            'org': {...carrierOrganization, 'transporterId': '27AAAAA0000A1Z5'}
          }));
      await mountSection(tester);
      await tapChange(tester);
      // What Save vehicle's refresh does first, before /v1/pilot/me answers.
      DriverSession.clearCarrierCache();
      await tester.enterText(transporterIdField(), '27aaaaa0000a1z5');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(find.text('27AAAAA0000A1Z5'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing);
      expect(find.text('Transporter ID saved.'), findsOneWidget);
      expect(DriverSession.transporterIdLoaded, isTrue,
          reason: 'the save told the app what is saved');
    });

    testWidgets("a wrong one shows the server's sentence, never HTTP 400",
        (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
            'error': 'invalid_transporter_id',
            'detail': transporterIdRule,
            'field': 'transporterId'
          }, 400));
      await mountSection(tester);
      await tapChange(tester);
      await tester.enterText(transporterIdField(), '12345');
      await tester.tap(find.text('Save transporter ID'));
      await tester.pumpAndSettle();
      expect(find.text(transporterIdRule), findsOneWidget);
      expect(find.textContaining('HTTP'), findsNothing);
      expect(DriverSession.transporterId, '29ABCDE1234F1Z5');
    });

    testWidgets('a dispatcher reads it with nothing to edit', (tester) async {
      signInAsCarrierLogin(office: true, alsoAllowed: ['trip.assign']);
      await mountSection(tester);
      expect(find.text('Transporter ID'), findsOneWidget, reason: 'the title');
      expect(find.text('29ABCDE1234F1Z5'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Save transporter ID'), findsNothing);
    });

    testWidgets('a driver does not see it', (tester) async {
      signInAsCarrierLogin(office: false);
      await mountSection(tester);
      expect(find.textContaining('Transporter ID'), findsNothing);
      expect(find.text('29ABCDE1234F1Z5'), findsNothing);
    });

    testWidgets('Profile reads it from /v1/pilot/me', (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      final principal = AuthorizationSession.principal;
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          request.path == '/v1/auth/me'
              ? jsonResponse({
                  'user': {'id': 'carrier-person'},
                  'organizations': [carrierOrganization],
                  'principal': principal,
                })
              : jsonResponse({
                  'organizations': [
                    {...carrierOrganization, 'transporterId': '27AAAAA0000A1Z5'}
                  ],
                  'vehicles': <Object>[],
                  'driverProfile': null,
                }));
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: const Scaffold(body: DriverProfileScreen())));
      await tester.pumpAndSettle();
      expect(DriverSession.transporterId, '27AAAAA0000A1Z5');
      expect(find.text('27AAAAA0000A1Z5'), findsOneWidget);
      expect(transporterIdField(), findsNothing,
          reason: 'a saved ID opens as text, not as a field');
    });

    testWidgets(
        'if Profile cannot load it, the owner gets no empty field whose Save would clear it',
        (tester) async {
      signInAsCarrierLogin(
          office: true, alsoAllowed: ['trip.assign', 'transporter_id.write']);
      final principal = AuthorizationSession.principal;
      api.dio.httpClientAdapter = MockApiAdapter((request) =>
          request.path == '/v1/auth/me'
              ? jsonResponse({
                  'user': {'id': 'carrier-person'},
                  'organizations': [carrierOrganization],
                  'principal': principal,
                })
              : jsonResponse({'error': 'unavailable'}, 500));
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: DriverTheme.theme(),
          home: const Scaffold(body: DriverProfileScreen())));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Could not load the transporter ID. Leave Profile and open it again to retry.'),
          findsOneWidget);
      expect(transporterIdField(), findsNothing);
      expect(find.text('Save transporter ID'), findsNothing);
    });
  });

  group('Transporter ID at sign-up', () {
    Future<List<Object?>> signUp(WidgetTester tester,
        {required String transporterId, int status = 201}) async {
      FlutterSecureStorage.setMockInitialValues({});
      api = Api('http://test');
      AuthorizationSession.clear();
      final sent = <Object?>[];
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        sent.add(request.data);
        return status == 201
            ? jsonResponse({
                'org': {'id': 'carrier-c'}
              }, 201)
            : jsonResponse({
                'error': 'invalid_transporter_id',
                'detail': transporterIdRule,
                'field': 'transporterId'
              }, status);
      });
      final router =
          GoRouter(initialLocation: '/driver/onboarding/register', routes: [
        GoRoute(
            path: '/driver/onboarding/register',
            builder: (_, __) => const DriverRegisterScreen()),
        GoRoute(
            path: '/driver/onboarding/otp',
            builder: (_, __) => const Scaffold(body: Text('Code screen'))),
      ]);
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text(transporterIdHelperText), findsOneWidget);
      for (final (label, value) in [
        ('Your full name', 'Synthetic Carrier C'),
        ('Phone (10 digits)', '8000000017'),
        ('Carrier / org display name', 'Synthetic Carrier C'),
        ('Your vehicle registration', 'KA05MN0001'),
        ('Transporter ID (optional)', transporterId),
      ]) {
        await tester.enterText(find.widgetWithText(TextField, label), value);
      }
      // PR 7: the size is a choice with nothing chosen, no longer a field prefilled with MEDIUM.
      await tester.tap(find.text('Medium'));
      await tester.tap(find.text('Create carrier & continue'));
      await tester.pumpAndSettle();
      return sent;
    }

    testWidgets('a typed transporter ID is sent with the sign-up',
        (tester) async {
      final sent = await signUp(tester, transporterId: ' 29abcde1234f1z5 ');
      expect((sent.single as Map)['transporterId'], '29abcde1234f1z5');
      expect((sent.single as Map)['vehicleClass'], 'MEDIUM',
          reason: 'the size chosen on the chips is the one sent');
      expect(find.text('Code screen'), findsOneWidget);
    });

    testWidgets('left empty, it is not sent at all', (tester) async {
      final sent = await signUp(tester, transporterId: '');
      expect((sent.single as Map).containsKey('transporterId'), isFalse);
    });

    testWidgets("a refused one shows the server's sentence and stays put",
        (tester) async {
      await signUp(tester, transporterId: '12345', status: 400);
      expect(find.text(transporterIdRule), findsOneWidget);
      expect(find.text('Code screen'), findsNothing);
    });

    testWidgets(
        'after a refusal, a successful try leaves no refusal on the code screen',
        (tester) async {
      await signUp(tester, transporterId: '12345', status: 400);
      expect(find.text(transporterIdRule), findsOneWidget);
      api.dio.httpClientAdapter = MockApiAdapter((request) => jsonResponse({
            'org': {'id': 'carrier-c'}
          }, 201));
      await tester.enterText(
          find.widgetWithText(TextField, 'Transporter ID (optional)'),
          '27AAAAA0000A1Z5');
      await tester.tap(find.text('Create carrier & continue'));
      await tester.pumpAndSettle();
      expect(find.text('Code screen'), findsOneWidget);
      expect(find.text(transporterIdRule), findsNothing,
          reason: 'the 10-second refusal is hidden when the next try starts');
    });
  });
}
