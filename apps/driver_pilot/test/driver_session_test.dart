import "dart:async";

import "package:dio/dio.dart";
import "package:driver_pilot/authorization_session.dart";
import "package:driver_pilot/driver_session.dart";
import "package:driver_pilot/pilot_api.dart";
import "package:flutter_test/flutter_test.dart";

/// Guards the sign-out race on `DriverSession`.
///
/// `Future.timeout` on the caller stops the waiting, not the request: Dio runs for up to
/// 45 seconds. Before the epoch guard, a `/v1/pilot/me` response that landed after a
/// sign-out wrote the previous driver's name, phone and org straight back into the shared
/// static session — on a shared phone, in front of the next driver.
void main() {
  late Completer<void> release;

  setUp(() {
    DriverSession.clear();
    lastRegisteredOrgId = null;
    api = Api("http://test");
    api.dio.interceptors.clear();
    release = Completer<void>();
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Hold the response open so the test can sign out mid-flight.
          await release.future;
          final auth = options.path.endsWith('/v1/auth/me');
          handler.resolve(Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: auth
                  ? const {
                      'user': {
                        'id': 'driver-1',
                        'fullName': 'Ravi Kumar',
                        'phone': '9876543210'
                      },
                      'organizations': [
                        {
                          'id': 'org_1',
                          'kind': 'CARRIER_FLEET',
                          'displayName': 'Ravi Transport',
                          'kycStatus': 'APPROVED'
                        },
                      ],
                      'principal': {
                        'organizationId': 'org_1',
                        'roles': ['CARRIER'],
                        'permissions': ['organization.profile.read'],
                      },
                    }
                  : const {
                      "user": {"fullName": "Ravi Kumar", "phone": "9876543210"},
                      "organizations": [
                        {
                          "id": "org_1",
                          "kind": "CARRIER_SOLO",
                          "displayName": "Ravi Transport",
                          "kycStatus": "APPROVED"
                        },
                      ],
                      "memberships": [
                        {"orgId": "org_1", "role": "OWNER_DRIVER"},
                      ],
                    }));
        },
      ),
    );
  });

  test("a refresh that lands after clear() does not repopulate the session",
      () async {
    final pending = DriverSession.refresh();

    // The driver signs out while the request is still open.
    DriverSession.clear();

    release.complete();
    final ok = await pending;

    expect(ok, isFalse, reason: "a superseded refresh must not report success");
    expect(DriverSession.userFullName, isNull);
    expect(DriverSession.userPhone, isNull);
    expect(DriverSession.carrierOrgId, isNull);
    expect(DriverSession.carrierOrgName, isNull);
    expect(DriverSession.carrierRole, isNull);
    expect(DriverSession.kycStatus, isNull);
    expect(DriverSession.hasCarrierOrg, isFalse);
    expect(lastRegisteredOrgId, isNull,
        reason: "the org-id fallback three money screens read");
  });

  test("a refresh that lands with no sign-out still populates the session",
      () async {
    final pending = DriverSession.refresh();
    release.complete();
    final ok = await pending;

    expect(ok, isTrue);
    expect(DriverSession.userPhone, "9876543210");
    expect(DriverSession.carrierOrgId, "org_1");
    expect(DriverSession.hasCarrierOrg, isTrue);
  });

  test(
      "a successful refresh with no carrier clears a leftover lastRegisteredOrgId",
      () async {
    lastRegisteredOrgId = "org_stale";
    api.dio.interceptors.clear();
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                "user": {"fullName": "Fleet Driver", "phone": "9000000001"},
                "organizations": <Map<String, dynamic>>[],
                "memberships": <Map<String, dynamic>>[],
              },
            ),
          );
        },
      ),
    );

    final ok = await DriverSession.refresh();

    expect(ok, isFalse);
    expect(DriverSession.hasCarrierOrg, isFalse);
    expect(lastRegisteredOrgId, isNull);
  });

  test("refresh and organization switch keep the signed-in session", () async {
    api.selectOrganization(null);
    api.dio.interceptors.clear();
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final selected = api.activeOrganizationId;
          final auth = options.path.endsWith("/v1/auth/me");
          handler.resolve(Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: 200,
            data: auth
                ? {
                    "user": {
                      "id": "driver-1",
                      "fullName": "Ravi Kumar",
                      "phone": "9876543210"
                    },
                    "organizations": [
                      {
                        "id": "org_1",
                        "kind": "CARRIER_FLEET",
                        "displayName": "Ravi Transport",
                        "kycStatus": "APPROVED"
                      },
                      {
                        "id": "org_2",
                        "kind": "CARRIER_FLEET",
                        "displayName": "Second Fleet",
                        "kycStatus": "APPROVED"
                      },
                    ],
                    if (selected != null)
                      "principal": {
                        "organizationId": selected,
                        "roles": ["CARRIER"],
                        "subrole": "OWNER",
                        "permissions": [
                          "organization.profile.read",
                          "load.read"
                        ],
                      },
                  }
                : {
                    "driverProfile": {"primaryVehicleId": "veh_1"},
                    "vehicles": [
                      {
                        "id": "veh_1",
                        "registrationNumber": "DL01AB1234",
                        "vehicleClass": "MEDIUM",
                        "capacityKg": 1000
                      },
                    ],
                  },
          ));
        },
      ),
    );

    var depth = 0;
    void listener() {
      depth++;
      expect(depth, lessThan(8),
          reason: "the session listener must not call back into session clear");
      if (!AuthorizationSession.signedIn || AuthorizationSession.switching) {
        DriverSession.clearCarrierCache();
      }
    }

    AuthorizationSession.revision.addListener(listener);
    addTearDown(() => AuthorizationSession.revision.removeListener(listener));

    await AuthorizationSession.refresh();
    expect(AuthorizationSession.signedIn, isTrue);

    api.selectOrganization("org_1");
    final ok = await DriverSession.refresh();
    expect(ok, isTrue, reason: "a signed-in carrier refresh has to finish");
    expect(AuthorizationSession.signedIn, isTrue,
        reason: "refresh must not wipe the session the listener is watching");
    expect(DriverSession.carrierOrgName, "Ravi Transport");
    expect(DriverSession.vehicleRegistrationNumber, "DL01AB1234");

    await AuthorizationSession.selectOrganization("org_2");
    expect(AuthorizationSession.signedIn, isTrue);
    expect(AuthorizationSession.organizationId, "org_2");
  });
}
