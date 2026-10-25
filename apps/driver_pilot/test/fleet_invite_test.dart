// Someone at another carrier cannot be invited, so the invite screen says so up front and shows the
// server sentence when it happens, and the Join a fleet screen does not promise otherwise.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';

const anotherCarrierSentence =
    'This number belongs to someone at another carrier and cannot be added yet.';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    api = Api('http://test');
    AuthorizationSession.clear();
    api.selectOrganization('carrier-a');
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path.endsWith('/v1/pilot/carrier/drivers/invite')) {
        return jsonResponse({
          'error': 'member_of_another_carrier',
          'detail': anotherCarrierSentence
        }, 409);
      }
      return jsonResponse({
        'user': {'id': 'carrier-owner'},
        'organizations': [
          {
            'id': 'carrier-a',
            'kind': 'CARRIER_FLEET',
            'displayName': 'Synthetic Carrier A'
          }
        ],
        'principal': {
          'organizationId': 'carrier-a',
          'roles': ['CARRIER'],
          'subrole': 'OWNER',
          'permissions': ['organization.member.invite'],
        },
      });
    });
  });

  test('a refused invite of someone at another carrier shows the server sentence',
      () {
    final options = RequestOptions(path: '/v1/pilot/carrier/drivers/invite');
    final error = DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: 409, data: {
        'error': 'member_of_another_carrier',
        'detail': anotherCarrierSentence
      }),
    );
    expect(formatApiError(error), anotherCarrierSentence);
  });

  testWidgets(
      'the invite screen says someone at another carrier cannot be added yet, and shows the sentence when refused',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DriverFleetInviteScreen())));
    await tester.pumpAndSettle();

    expect(
        find.text(
            'Invite a driver who already registered their phone. Someone at another carrier cannot be added yet. A solo company becomes a fleet when you add drivers.'),
        findsOneWidget);
    expect(find.textContaining('or used Join a fleet'), findsNothing);

    await tester.enterText(
        find.widgetWithText(TextField, 'Driver phone (10 digits)'),
        '8000000021');
    await tester.enterText(
        find.widgetWithText(TextField, 'Vehicle registration'), 'TEST-INVITE');
    await tester.ensureVisible(find.text('Invite driver'));
    await tester.tap(find.text('Invite driver'));
    await tester.pumpAndSettle();

    expect(find.text(anotherCarrierSentence), findsOneWidget);
  });

  testWidgets(
      'the Join a fleet screen says someone at another carrier cannot be added yet',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DriverJoinScreen()));

    expect(
        find.text(
            'Create a personal account so your carrier admin can invite you to their company. You do not get a carrier company from this step. If you already work for another carrier, you cannot be added yet.'),
        findsOneWidget);
  });
}
