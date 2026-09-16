import "package:dio/dio.dart";
import "package:flutter/foundation.dart";

import "pilot_api.dart";

/// In-memory carrier session refreshed from `/v1/pilot/me`.
abstract final class DriverSession {
  /// Bumps when session fields change, so the driver shell rebuilds. Without this the
  /// shell keeps showing five tabs after a sign-out, because it only re-runs on navigation.
  static final Listenable listenable = ValueNotifier<int>(0);

  static void _notifyListeners() {
    (listenable as ValueNotifier<int>).value++;
  }

  /// True when the last refresh failed because the server rejected the token, as opposed
  /// to the request never arriving. Without it an expired session is reported as no signal
  /// and the only button offered ("Try again") can never succeed.
  static bool lastRefreshRejected = false;

  /// Bumped by [clear]. A refresh captures it before its await and discards its own writes
  /// if it changed, because `Future.timeout` on the caller stops the waiting, not the
  /// request: Dio runs for up to 45s. Without this a response arriving after a sign-out
  /// writes the previous driver's name, phone and org straight back in, on a shared phone.
  static int _epoch = 0;
  static String? carrierOrgId;
  static String? carrierOrgName;
  static String? carrierRole;
  static String? userFullName;
  static String? userPhone;
  static String? kycStatus;
  static String? vehicleId;
  static String? vehicleRegistrationNumber;
  static String? vehicleClass;
  static double? vehicleCapacityKg;

  static bool get hasCarrierOrg => carrierOrgId != null && carrierOrgId!.isNotEmpty;

  static bool get canInviteDrivers {
    final r = carrierRole;
    return r == "OWNER_DRIVER" || r == "OWNER" || r == "DISPATCHER";
  }

  static bool get payoutSetupComplete => kycStatus == "SUBMITTED" || kycStatus == "APPROVED";

  static Future<bool> refresh() async {
    final epoch = _epoch;
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/pilot/me");
      // Everything below this line writes shared session state. If the session was cleared
      // while this request was in flight, those writes belong to a user who has signed out.
      if (epoch != _epoch) return false;
      final user = r.data?["user"];
      if (user is Map<String, dynamic>) {
        userFullName = user["fullName"] as String?;
        userPhone = user["phone"] as String?;
      }
      carrierRole = null;
      final oid = firstCarrierOrgIdFromPilotMe(r.data);
      if (oid != null) {
        carrierOrgId = oid;
        lastRegisteredOrgId = oid;
        carrierOrgName = carrierOrgDisplayNameFromPilotMe(r.data, oid);
        final orgs = r.data?["organizations"];
        final memberships = r.data?["memberships"];
        if (orgs is List) {
          for (final o in orgs) {
            if (o is Map<String, dynamic> && o["id"] == oid) {
              kycStatus = o["kycStatus"] as String?;
              break;
            }
          }
        }
        if (memberships is List) {
          for (final m in memberships) {
            if (m is Map<String, dynamic> && m["orgId"]?.toString() == oid) {
              carrierRole = m["role"]?.toString();
              break;
            }
          }
        }
      } else {
        carrierOrgId = null;
        carrierOrgName = null;
        kycStatus = null;
      }

      vehicleId = null;
      vehicleRegistrationNumber = null;
      vehicleClass = null;
      vehicleCapacityKg = null;
      final profile = r.data?["driverProfile"];
      final vehicles = r.data?["vehicles"];
      if (profile is Map<String, dynamic> && vehicles is List) {
        final primaryId = profile["primaryVehicleId"]?.toString();
        if (primaryId != null && primaryId.isNotEmpty) {
          for (final v in vehicles) {
            if (v is Map<String, dynamic> && v["id"]?.toString() == primaryId) {
              vehicleId = primaryId;
              vehicleRegistrationNumber = v["registrationNumber"]?.toString();
              vehicleClass = v["vehicleClass"]?.toString();
              final cap = v["capacityKg"];
              if (cap is num) vehicleCapacityKg = cap.toDouble();
              break;
            }
          }
        }
      }
      lastRefreshRejected = false;
      _notifyListeners();
      return true;
    } on DioException catch (e) {
      if (epoch != _epoch) return false;
      final status = e.response?.statusCode;
      lastRefreshRejected = status == 401 || status == 403;
      return false;
    } catch (_) {
      if (epoch != _epoch) return false;
      lastRefreshRejected = false;
      return false;
    }
  }

  static void clear() {
    // Invalidates any refresh already in flight so its response cannot write these fields
    // back after the user has signed out.
    _epoch++;
    // Not a DriverSession field, but it survives sign-out otherwise and is used as an
    // org-id fallback on the earnings, payout-setup and payout-history screens. On a shared
    // phone that sends one driver's org id with the next driver's bank details.
    lastRegisteredOrgId = null;
    lastRefreshRejected = false;
    carrierOrgId = null;
    carrierOrgName = null;
    carrierRole = null;
    userFullName = null;
    userPhone = null;
    kycStatus = null;
    vehicleId = null;
    vehicleRegistrationNumber = null;
    vehicleClass = null;
    vehicleCapacityKg = null;
    _notifyListeners();
  }
}
