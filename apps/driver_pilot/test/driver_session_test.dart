import "dart:async";

import "package:dio/dio.dart";
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
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                "user": {"fullName": "Ravi Kumar", "phone": "9876543210"},
                "organizations": [
                  {"id": "org_1", "kind": "CARRIER_SOLO", "displayName": "Ravi Transport", "kycStatus": "APPROVED"},
                ],
                "memberships": [
                  {"orgId": "org_1", "role": "OWNER_DRIVER"},
                ],
              },
            ),
          );
        },
      ),
    );
  });

  test("a refresh that lands after clear() does not repopulate the session", () async {
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
    expect(lastRegisteredOrgId, isNull, reason: "the org-id fallback three money screens read");
  });

  test("a refresh that lands with no sign-out still populates the session", () async {
    final pending = DriverSession.refresh();
    release.complete();
    final ok = await pending;

    expect(ok, isTrue);
    expect(DriverSession.userPhone, "9876543210");
    expect(DriverSession.carrierOrgId, "org_1");
    expect(DriverSession.hasCarrierOrg, isTrue);
  });
}
