import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'pilot_api.dart';

/// Only the server-resolved principal for the selected organization grants UI access.
abstract final class AuthorizationSession {
  static final revision = ValueNotifier<int>(0);
  static Map<String, dynamic>? user;
  static Map<String, dynamic>? principal;
  static List<Map<String, dynamic>> organizations = [];
  static bool initialized = false;
  static bool switching = false;
  static String? error;
  static Future<bool>? _refreshing;
  static int _generation = 0;

  static bool get signedIn => user != null;
  static String? get organizationId => principal?['organizationId'] as String?;
  static Map<String, dynamic>? get organization {
    for (final org in organizations) {
      if (org['id'] == organizationId) return org;
    }
    return null;
  }

  static bool hasRole(String role) =>
      (principal?['roles'] as List? ?? []).contains(role);
  static bool can(String permission) =>
      !switching &&
      (principal?['permissions'] as List? ?? []).contains(permission);
  static String get home => hasRole('SHIPPER')
      ? '/customer'
      : hasRole('CARRIER')
          ? '/driver/loads'
          : '/workspace';
  static String get scopeKey => '${user?['id']}:$organizationId';

  static void bind() {
    api.onIdentityChanged = clear;
    api.onAuthorizationFailure = () {
      refresh();
    };
  }

  static void clear() {
    _generation++;
    _refreshing = null;
    user = null;
    principal = null;
    organizations = [];
    error = null;
    switching = false;
    initialized = true;
    revision.value++;
  }

  static Future<void> signOut() async {
    await api.clearToken();
    clear();
  }

  static Future<bool> refresh() {
    bind();
    final generation = _generation;
    return _refreshing ??= _load(generation).whenComplete(() {
      if (generation == _generation) _refreshing = null;
    });
  }

  static Future<bool> _load(int generation) async {
    final before =
        jsonEncode([user, principal, organizations, initialized, error]);
    try {
      Response<Map<String, dynamic>> response;
      try {
        response = await api.get<Map<String, dynamic>>('/v1/auth/me');
      } on DioException catch (e) {
        if (generation != _generation) return false;
        if (api.activeOrganizationId == null ||
            ![400, 403].contains(e.response?.statusCode)) {
          rethrow;
        }
        // A revoked membership must not strand the user in an invalid selection.
        api.selectOrganization(null);
        response = await api.get<Map<String, dynamic>>('/v1/auth/me');
      }
      if (generation != _generation) return false;
      final data = response.data ?? {};
      user = data['user'] as Map<String, dynamic>?;
      organizations = (data['organizations'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      principal = data['principal'] as Map<String, dynamic>?;
      if (principal != null &&
          !organizations.any((org) => org['id'] == organizationId)) {
        principal = null;
      }
      if (api.activeOrganizationId != organizationId) {
        api.selectOrganization(organizationId);
      }
      error = null;
    } catch (e) {
      if (generation != _generation) return false;
      principal =
          null; // Never retain grants after a failed authorization refresh.
      if (e is DioException && e.response?.statusCode == 401) {
        user = null;
        organizations = [];
        api.selectOrganization(null);
        error = null;
      } else {
        error = formatApiError(e);
      }
    } finally {
      if (generation == _generation) {
        initialized = true;
        if (before !=
            jsonEncode([user, principal, organizations, initialized, error])) {
          revision.value++;
        }
      }
    }
    return signedIn;
  }

  static Future<void> selectOrganization(String id) async {
    if (!organizations.any((org) => org['id'] == id) || switching) return;
    _generation++;
    _refreshing = null;
    switching = true;
    principal = null;
    api.selectOrganization(id);
    revision.value++;
    await refresh();
    switching = false;
    revision.value++;
  }
}
