import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pilot_api.dart';

const _channelId = 'shipment_updates';
const _channelName = 'Shipment updates';
const _pendingNotificationKey = 'push_pending_notification';
const _installationIdKey = 'push_installation_id';
const _consentKey = 'push_alerts_consented';
const _consentOwnerKey = 'push_alerts_consent_owner';
const _deviceIdKey = 'push_device_id';
const _deviceGenerationKey = 'push_device_generation';
const _deviceOwnerKey = 'push_device_owner';
const _revocationKey = 'push_pending_revocation';
const shipmentUpdateNotificationId = 0;

class PushPayload {
  const PushPayload({required this.notificationId, this.presentationKey});
  final String notificationId;
  final String? presentationKey;

  static PushPayload? parse(Map<String, dynamic> data,
      {bool requirePresentationKey = false}) {
    final id = data['notificationId'];
    final key = data['presentationKey'];
    if (data['schemaVersion'] != '1' ||
        id is! String ||
        id.isEmpty ||
        id.length > 128) {
      return null;
    }
    if (requirePresentationKey &&
        (key is! String || key.isEmpty || key.length > 128)) {
      return null;
    }
    return PushPayload(
      notificationId: id,
      presentationKey: key is String ? key : null,
    );
  }
}

AndroidNotificationDetails shipmentUpdateNotificationDetails(String tag) =>
    AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Updates about your shipments',
      importance: Importance.high,
      priority: Priority.high,
      tag: tag,
      visibility: NotificationVisibility.private,
    );

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  final options = _firebaseOptions;
  if (options != null && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }
  // Notification messages are rendered by Android while the app is backgrounded.
  // Keep this handler free of network work and sensitive payload processing.
}

const _firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
const _firebaseSenderId =
    String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
const _firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

FirebaseOptions? get _firebaseOptions {
  if (_firebaseApiKey.isEmpty ||
      _firebaseAppId.isEmpty ||
      _firebaseSenderId.isEmpty ||
      _firebaseProjectId.isEmpty) return null;
  return FirebaseOptions(
    apiKey: _firebaseApiKey,
    appId: _firebaseAppId,
    messagingSenderId: _firebaseSenderId,
    projectId: _firebaseProjectId,
  );
}

class PushOpenRoute {
  const PushOpenRoute({required this.organizationId, required this.shipmentId});
  final String organizationId;
  final String shipmentId;
}

/// Android FCM lifecycle. The app's canonical inbox remains the source of truth.
class PushNotifications {
  PushNotifications._();
  static final instance = PushNotifications._();

  static const _storage = FlutterSecureStorage();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  Future<void> Function(String notificationId)? _onOpen;
  bool Function()? _isAuthenticated;
  String? Function()? _userId;
  bool _initialized = false;
  bool _localReady = false;
  bool _firebaseConfigured = false;
  bool _registered = false;
  int _registrationEpoch = 0;
  Future<void>? _registrationInFlight;
  Future<void> _lifecycleQueue = Future<void>.value();
  bool _identityTransitionInProgress = false;

  bool get available => _firebaseConfigured && _isAndroid;
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize({
    required Future<void> Function(String notificationId) onOpen,
    required bool Function() isAuthenticated,
    required String? Function() userId,
  }) async {
    _onOpen = onOpen;
    _isAuthenticated = isAuthenticated;
    _userId = userId;
    if (_initialized || !_isAndroid) return;
    _initialized = true;
    final options = _firebaseOptions;
    if (options == null) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_notification'),
        ),
        onDidReceiveNotificationResponse: (response) {
          unawaited(_handlePayload(response.payload));
        },
      );
      _localReady = true;
      final android = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Updates about your shipments',
        importance: Importance.high,
      ));
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(_showLocal);
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => unawaited(_handleData(message.data)),
      );
      _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => unawaited(syncRegistration()),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) await _handleData(initial.data);
      final launch = await _local.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        await _handlePayload(response.payload);
      }
      _firebaseConfigured = true;
      await _drainPendingRevocation();
      await syncRegistration();
      await _drainPendingOpen();
    } catch (_) {
      // Firebase is optional for local builds; in-app notifications continue to work.
      _firebaseConfigured = false;
    }
  }

  Future<bool> enableAlerts() async {
    if (!available || !(_isAuthenticated?.call() ?? false)) return false;
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final localEnabled = await android?.areNotificationsEnabled() ?? true;
    if (!localEnabled) return false;
    final owner = await _currentUserId();
    if (owner == null) return false;
    await _storage.write(key: _consentKey, value: 'true');
    await _storage.write(key: _consentOwnerKey, value: owner);
    await syncRegistration();
    return _registered;
  }

  Future<bool> get optedIn async =>
      available && await _storage.read(key: _consentKey) == 'true';

  Future<void> syncRegistration() {
    if (_identityTransitionInProgress) return Future<void>.value();
    final pending = _registrationInFlight;
    if (pending != null) return pending;
    final epoch = _registrationEpoch;
    final operation = _serializeLifecycle(() => _syncRegistration(epoch));
    _registrationInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_registrationInFlight, operation)) {
        _registrationInFlight = null;
      }
    });
  }

  Future<void> _syncRegistration(int epoch) async {
    _registered = false;
    if (epoch != _registrationEpoch ||
        _identityTransitionInProgress ||
        !available ||
        !await optedIn ||
        !(_isAuthenticated?.call() ?? false) ||
        !await api.hasBearerToken()) return;
    try {
      await _drainPendingRevocationUnlocked();
      final owner = await _currentUserId();
      if (owner == null ||
          await _storage.read(key: _consentOwnerKey) != owner) {
        return;
      }
      if (!_registrationIsCurrent(epoch, owner)) return;
      final permission = await _permissionState();
      if (!_registrationIsCurrent(epoch, owner)) return;
      if (!permission.$1 || !permission.$2) {
        await _revokeStoredRegistration();
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null ||
          token.isEmpty ||
          !_registrationIsCurrent(epoch, owner)) return;
      final installationId = await _installationId();
      if (!_registrationIsCurrent(epoch, owner)) return;
      final response = await api.put<Map<String, dynamic>>(
        '/v1/me/push-devices',
        data: {
          'installationId': installationId,
          'token': token,
          'consented': true,
          'permissionGranted': permission.$1,
          'channelEnabled': permission.$2,
        },
      );
      final data = response.data ?? const <String, dynamic>{};
      if (!_registrationIsCurrent(epoch, owner)) {
        await _revokeRegistrationResponse(data, owner);
        return;
      }
      await _storage.write(
          key: _deviceIdKey, value: data['deviceId']?.toString());
      await _storage.write(
          key: _deviceGenerationKey,
          value: data['ownershipGeneration']?.toString());
      await _storage.write(key: _deviceOwnerKey, value: owner);
      _registered = true;
    } catch (_) {
      // FCM registration is best-effort; the inbox remains available.
    }
  }

  Future<void> revokeForCurrentUser() async {
    _identityTransitionInProgress = true;
    _registrationEpoch++;
    try {
      await _serializeLifecycle(() async {
        await _revokeStoredRegistration();
        await _storage.delete(key: _consentKey);
        await _storage.delete(key: _consentOwnerKey);
        await _storage.delete(key: _pendingNotificationKey);
        if (_localReady) await _local.cancelAll();
      });
    } catch (_) {
      // Keep registration fenced until Api confirms the credential transition.
      // Any durable revocation marker is retried on the next authenticated session.
    }
  }

  /// Fence push work and retain an account-bound revocation marker when the
  /// server has rejected an established session. No authenticated revoke call
  /// is possible here; the marker is replayed after that same account signs in.
  Future<void> onAuthorizationLost({String? establishedUserId}) async {
    _identityTransitionInProgress = true;
    _registrationEpoch++;
    _registered = false;
    try {
      await _serializeLifecycle(() async {
        final owner = await _storage.read(key: _deviceOwnerKey);
        final deviceId = await _storage.read(key: _deviceIdKey);
        final generation =
            int.tryParse(await _storage.read(key: _deviceGenerationKey) ?? '');
        if (owner != null &&
            deviceId != null &&
            generation != null &&
            (establishedUserId == null || establishedUserId == owner)) {
          await _storage.write(
            key: _revocationKey,
            value: jsonEncode({
              'userId': owner,
              'deviceId': deviceId,
              'generation': generation,
            }),
          );
        }
        await _storage.delete(key: _consentKey);
        await _storage.delete(key: _consentOwnerKey);
        await _storage.delete(key: _pendingNotificationKey);
        if (_localReady) await _local.cancelAll();
      });
    } catch (_) {
      // Keep registration fenced until the next credential transition. Any
      // marker written above remains durable for a later authenticated retry.
    }
  }

  void onCredentialChanged() {
    _identityTransitionInProgress = false;
  }

  Future<void> refreshPermissionState() async {
    if (!available || !await optedIn || !(_isAuthenticated?.call() ?? false)) {
      return;
    }
    try {
      final state = await _permissionState();
      if (!state.$1 || !state.$2) {
        _identityTransitionInProgress = true;
        _registrationEpoch++;
        try {
          await _serializeLifecycle(_revokeStoredRegistration);
        } catch (_) {
          // Preserve the local revocation marker for the next reconciliation.
        } finally {
          _identityTransitionInProgress = false;
        }
        return;
      }
      await syncRegistration();
    } catch (_) {
      // Keep the last registration on a transient platform query failure.
    }
  }

  Future<void> _revokeStoredRegistration() async {
    _registered = false;
    final owner = await _storage.read(key: _deviceOwnerKey);
    final deviceId = await _storage.read(key: _deviceIdKey);
    final generation =
        int.tryParse(await _storage.read(key: _deviceGenerationKey) ?? '');
    if (owner != null && deviceId != null && generation != null) {
      final existingMarker = await _storage.read(key: _revocationKey);
      if (existingMarker != null) {
        try {
          final decoded = jsonDecode(existingMarker) as Map<String, dynamic>;
          if (decoded['deviceId'] == deviceId &&
              decoded['userId'] == owner &&
              decoded['generation'] is int &&
              (decoded['generation'] as int) >= generation) {
            await _revokeMarker(existingMarker, expectedUserId: owner);
            return;
          }
        } catch (_) {
          // Replace malformed markers with the current registration below.
        }
      }
      final marker = jsonEncode({
        'userId': owner,
        'deviceId': deviceId,
        'generation': generation,
      });
      await _storage.write(key: _revocationKey, value: marker);
      await _revokeMarker(marker, expectedUserId: owner);
    }
  }

  Future<void> onAuthenticatedSessionChanged(String? userId) async {
    if (userId == null) {
      await _serializeLifecycle(() async {
        await _storage.delete(key: _pendingNotificationKey);
        if (_localReady) await _local.cancelAll();
      });
      return;
    }
    await _drainPendingRevocation(expectedUserId: userId);
    await syncRegistration();
    await _drainPendingOpen();
  }

  bool _registrationIsCurrent(int epoch, String owner) =>
      epoch == _registrationEpoch &&
      (_isAuthenticated?.call() ?? false) &&
      _userId?.call() == owner;

  Future<(bool, bool)> _permissionState() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final appEnabled = await android?.areNotificationsEnabled() ?? true;
    final channels = await android?.getNotificationChannels();
    final matching = channels?.where((item) => item.id == _channelId) ?? [];
    final channel = matching.isEmpty ? null : matching.first;
    final permissionEnabled =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    return (
      permissionEnabled && appEnabled,
      channel == null || channel.importance != Importance.none
    );
  }

  Future<void> _revokeRegistrationResponse(
      Map<String, dynamic> data, String owner) async {
    final deviceId = data['deviceId']?.toString();
    final generation =
        int.tryParse(data['ownershipGeneration']?.toString() ?? '');
    if (deviceId == null || generation == null) return;
    await _storage.write(key: _deviceIdKey, value: deviceId);
    await _storage.write(
        key: _deviceGenerationKey, value: generation.toString());
    await _storage.write(key: _deviceOwnerKey, value: owner);
    final marker = jsonEncode({
      'userId': owner,
      'deviceId': deviceId,
      'generation': generation,
    });
    try {
      await _storage.write(key: _revocationKey, value: marker);
      await _revokeMarker(marker, expectedUserId: owner);
    } catch (_) {
      // Logout's normal revocation marker handles transient failures.
    }
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
  }

  Future<void> _showLocal(RemoteMessage message) async {
    final data = message.data;
    final payload = PushPayload.parse(data, requirePresentationKey: true);
    if (payload == null) return;
    await _local.show(
      shipmentUpdateNotificationId,
      'Shipment update',
      'There is a new update about one of your shipments.',
      NotificationDetails(
          android: shipmentUpdateNotificationDetails(payload.presentationKey!)),
      payload: jsonEncode(
          {'schemaVersion': '1', 'notificationId': payload.notificationId}),
    );
  }

  Future<void> _handleData(Map<String, dynamic> data) async {
    final payload = PushPayload.parse(data);
    if (payload == null) return;
    await _queueOpen(payload.notificationId);
  }

  Future<void> _handlePayload(String? payload) async {
    if (payload == null || payload.length > 512) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) await _handleData(data);
    } catch (_) {
      // Ignore malformed, stale, or externally forged local notification payloads.
    }
  }

  Future<void> _queueOpen(String id) async {
    if (id.length > 128) return;
    await _serializeLifecycle(() => _storage.write(
          key: _pendingNotificationKey,
          value: jsonEncode({
            'schemaVersion': '1',
            'notificationId': id,
            'expiresAt': DateTime.now()
                .add(const Duration(minutes: 15))
                .millisecondsSinceEpoch,
          }),
        ));
    await _drainPendingOpen();
  }

  Future<void> _drainPendingOpen() async {
    final notificationId = await _serializeLifecycle(() async {
      if (!await api.hasBearerToken() || !(_isAuthenticated?.call() ?? false))
        return null;
      final raw = await _storage.read(key: _pendingNotificationKey);
      if (raw == null) return null;
      String? id;
      try {
        final pending = jsonDecode(raw);
        if (pending is Map<String, dynamic> &&
            pending['schemaVersion'] == '1' &&
            pending['notificationId'] is String &&
            pending['expiresAt'] is int &&
            (pending['expiresAt'] as int) >=
                DateTime.now().millisecondsSinceEpoch) {
          id = pending['notificationId'] as String;
        }
      } catch (_) {
        // Remove malformed or expired values atomically with the read.
      }
      if (await _storage.read(key: _pendingNotificationKey) == raw) {
        await _storage.delete(key: _pendingNotificationKey);
      }
      return id;
    });
    if (notificationId == null) return;
    try {
      // Release the lifecycle queue before any API, organization-selection, or
      // navigation await; a later tap must still replace the queued route.
      await _onOpen?.call(notificationId);
    } catch (_) {
      // A stale/unauthorized push must never bypass server authorization.
    }
  }

  Future<String> _installationId() async {
    var id = await _storage.read(key: _installationIdKey);
    if (id != null && id.length >= 16) return id;
    final random = Random.secure();
    id = List<int>.generate(32, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _installationIdKey, value: id);
    return id;
  }

  Future<String?> _currentUserId() async {
    try {
      final response = await api.get<Map<String, dynamic>>('/v1/auth/me');
      return response.data?['user']?['id']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _drainPendingRevocation({String? expectedUserId}) async {
    await _serializeLifecycle(
        () => _drainPendingRevocationUnlocked(expectedUserId: expectedUserId));
  }

  Future<void> _drainPendingRevocationUnlocked({String? expectedUserId}) async {
    final marker = await _storage.read(key: _revocationKey);
    if (marker == null) return;
    try {
      final decoded = jsonDecode(marker);
      if (decoded is! Map<String, dynamic> ||
          decoded['userId'] is! String ||
          decoded['deviceId'] is! String ||
          decoded['generation'] is! int) return;
      final owner = decoded['userId'] as String;
      if (expectedUserId != null && owner != expectedUserId) return;
      await _revokeMarker(marker, expectedUserId: owner);
    } catch (_) {
      // Retain the account-bound marker for the next authenticated reconnect.
    }
  }

  Future<void> _revokeMarker(String marker,
      {required String expectedUserId}) async {
    final decoded = jsonDecode(marker) as Map<String, dynamic>;
    final actualUserId = await _currentUserId();
    if (actualUserId != expectedUserId) return;
    try {
      await api.delete<Map<String, dynamic>>(
        '/v1/me/push-devices/${Uri.encodeComponent(decoded['deviceId'] as String)}',
        data: {'ownershipGeneration': decoded['generation']},
      );
      if (await _storage.read(key: _revocationKey) == marker) {
        await _storage.delete(key: _revocationKey);
      }
      final currentDeviceId = await _storage.read(key: _deviceIdKey);
      final currentGeneration =
          int.tryParse(await _storage.read(key: _deviceGenerationKey) ?? '');
      final currentOwner = await _storage.read(key: _deviceOwnerKey);
      if (currentDeviceId == decoded['deviceId'] &&
          currentGeneration == decoded['generation'] &&
          currentOwner == expectedUserId) {
        await _storage.delete(key: _deviceIdKey);
        await _storage.delete(key: _deviceGenerationKey);
        await _storage.delete(key: _deviceOwnerKey);
      }
    } catch (_) {
      // The marker is replayed only after the same account authenticates again.
    }
  }

  Future<T> _serializeLifecycle<T>(Future<T> Function() operation) {
    final result = _lifecycleQueue.then((_) => operation());
    _lifecycleQueue =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
