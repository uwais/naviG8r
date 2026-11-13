import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _draftStorage = FlutterSecureStorage();

String conversationDraftKey(String scope, String conversationId) =>
    'conversation_draft_${Uri.encodeComponent(scope)}_${Uri.encodeComponent(conversationId)}';

abstract final class ConversationDrafts {
  static final Map<String, Future<void>> _pendingWrites = {};

  static String key(String scope, String conversationId) =>
      conversationDraftKey(scope, conversationId);

  static Future<Map<String, String>?> read(
      String scope, String conversationId) async {
    final draftKey = key(scope, conversationId);
    await _pendingWrites[draftKey];
    final raw = await _draftStorage.read(key: draftKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is Map &&
          value['body'] is String &&
          value['clientRequestId'] is String) {
        return {
          'body': value['body'] as String,
          'clientRequestId': value['clientRequestId'] as String
        };
      }
    } catch (_) {}
    return null;
  }

  static Future<void> write(String scope, String conversationId, String body,
      String requestId) async {
    final key = ConversationDrafts.key(scope, conversationId);
    final previous = _pendingWrites[key] ?? Future<void>.value();
    final operation = previous.catchError((Object _) {}).then((_) async {
      if (body.isEmpty) {
        await _draftStorage.delete(key: key);
        return;
      }
      await _draftStorage.write(
          key: key,
          value: jsonEncode({'body': body, 'clientRequestId': requestId}));
    });
    _pendingWrites[key] = operation;
    try {
      await operation;
    } finally {
      if (identical(_pendingWrites[key], operation)) {
        _pendingWrites.remove(key);
      }
    }
  }

  static Future<void> clearAll() async {
    final all = await _draftStorage.readAll();
    for (final key
        in all.keys.where((key) => key.startsWith('conversation_draft_'))) {
      await _draftStorage.delete(key: key);
    }
  }
}
