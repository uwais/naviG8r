// ignore_for_file: deprecated_member_use

// The messages screen for one shipment: its events and messages, and sending a reply.
import 'dart:async';

import 'package:flutter/material.dart';

import 'app_in_background.dart';
import 'authorization_session.dart';
import 'conversation_drafts.dart';
import 'notice_words.dart';
import 'pilot_api.dart';
import 'plain_error_sentence.dart';

const _navy = Color(0xFF122C53);
const _background = Color(0xFFF4F7FA);
const _muted = Color(0xFF64748B);

String _newClientRequestId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';

Future<void> openShipmentConversation(
        BuildContext context, String shipmentId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShipmentConversationScreen(shipmentId: shipmentId),
    ));

class ShipmentConversationScreen extends StatefulWidget {
  const ShipmentConversationScreen({required this.shipmentId, super.key});
  final String shipmentId;

  @override
  State<ShipmentConversationScreen> createState() =>
      _ShipmentConversationScreenState();
}

class _ShipmentConversationScreenState
    extends State<ShipmentConversationScreen> {
  final TextEditingController _composer = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _loadingEarlier = false;
  bool _sending = false;
  bool _canSend = true;
  String? _sendingBody;
  String? _sendingRequestId;
  String? _nextBefore;
  Map<String, dynamic>? _readWatermark;
  String? _error;
  String _clientRequestId = _newClientRequestId();
  String? _lastFailedBody;
  Timer? _poll;
  late final AppLifecycleListener _lifecycle;
  String get _path =>
      '/v1/shipments/${widget.shipmentId}/conversation/timeline';
  String get _sendPath =>
      '/v1/shipments/${widget.shipmentId}/conversation/messages';
  String get _scope => AuthorizationSession.scopeKey;

  Future<void> _load({bool restoreDraft = false}) async {
    try {
      final response = await api.get<Map<String, dynamic>>(_path);
      if (!mounted) return;
      final raw = response.data?['items'];
      final watermark = response.data?['readWatermark'];
      final roles = AuthorizationSession.principal?['roles'];
      final isOps = roles is List && roles.contains('OPS');
      setState(() {
        _messages =
            raw is List ? raw.whereType<Map<String, dynamic>>().toList() : [];
        _nextBefore = response.data?['nextBefore']?.toString();
        _readWatermark =
            watermark is Map ? Map<String, dynamic>.from(watermark) : null;
        _canSend = response.data?['canSend'] == true &&
            AuthorizationSession.can(
                isOps ? 'conversation.support_send' : 'conversation.send');
        _error = null;
        _loading = false;
      });
      if (_readWatermark != null) {
        try {
          await api.post('/v1/shipments/${widget.shipmentId}/conversation/read',
              data: {'readWatermark': _readWatermark});
        } catch (_) {}
      }
      if (restoreDraft) {
        final draft = await ConversationDrafts.read(_scope, widget.shipmentId);
        if (!mounted || draft == null) return;
        _clientRequestId = draft['clientRequestId']!;
        // Treat the restored body as a possibly failed submission: if the user
        // edits it, the new payload must get a fresh idempotency key.
        _lastFailedBody = draft['body'];
        _composer.value = TextEditingValue(
            text: draft['body']!,
            selection: TextSelection.collapsed(offset: draft['body']!.length));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = plainErrorSentence(error,
            'Could not load messages. Check your connection, then try again.');
        _loading = false;
      });
    }
  }

  Future<void> _loadEarlier() async {
    final cursor = _nextBefore;
    if (cursor == null || _loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    try {
      final response = await api.get<Map<String, dynamic>>(
        _path,
        query: {'before': cursor},
      );
      if (!mounted) return;
      final raw = response.data?['items'];
      final older = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _messages = [...older, ..._messages];
        _nextBefore = response.data?['nextBefore']?.toString();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(error,
            'Could not load earlier messages. Check your connection, then try again.'));
      }
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  void _onChanged(String value) {
    if (_sending &&
        value.trim() != _sendingBody &&
        _clientRequestId == _sendingRequestId) {
      // A new draft typed during an in-flight send needs its own retry identity.
      _clientRequestId = _newClientRequestId();
      _lastFailedBody = null;
    }
    if (_lastFailedBody != null && value != _lastFailedBody) {
      _clientRequestId = _newClientRequestId();
      _lastFailedBody = null;
    }
    unawaited(ConversationDrafts.write(
        _scope, widget.shipmentId, value, _clientRequestId));
  }

  Future<void> _send() async {
    final body = _composer.text.trim();
    if (!_canSend || _sending || body.isEmpty) return;
    final requestId = _clientRequestId;
    _sendingBody = body;
    _sendingRequestId = requestId;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>(_sendPath,
          data: {'body': body, 'clientRequestId': requestId});
      final submittedDraftIsCurrent =
          _composer.text.trim() == body && _clientRequestId == requestId;
      if (submittedDraftIsCurrent) {
        _clientRequestId = _newClientRequestId();
        _lastFailedBody = null;
        // Clear the submitted text before awaiting secure storage. Any new text
        // entered while cleanup is pending is queued after this delete.
        _composer.clear();
        await ConversationDrafts.write(
            _scope, widget.shipmentId, '', requestId);
      }
      await _load();
    } catch (error) {
      final submittedDraftIsCurrent =
          _composer.text.trim() == body && _clientRequestId == requestId;
      if (submittedDraftIsCurrent) {
        _lastFailedBody = body;
        await ConversationDrafts.write(
            _scope, widget.shipmentId, body, requestId);
      }
      if (mounted) {
        setState(() => _error = plainErrorSentence(
            error, 'Could not send. Check your connection, then try again.'));
      }
    } finally {
      _sendingBody = null;
      _sendingRequestId = null;
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load(restoreDraft: true);
    // A load also marks the messages read, so none runs while the phone is in a pocket.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!appIsInBackground) _load();
    });
    _lifecycle = AppLifecycleListener(onShow: _load);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        appBar: AppBar(title: const Text('Messages')),
        body: Column(children: [
          if (!_canSend && !_loading)
            const MaterialBanner(
                content: Text('You can read this conversation, but not reply.'),
                actions: [SizedBox.shrink()]),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child:
                    Text(_error!, style: const TextStyle(color: Colors.red))),
          if (_nextBefore != null)
            TextButton.icon(
              onPressed: _loadingEarlier ? null : _loadEarlier,
              icon: _loadingEarlier
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.history),
              label: const Text('Show earlier messages'),
            ),
          Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, reverseIndex) {
                          final message =
                              _messages[_messages.length - 1 - reverseIndex];
                          if (message['type'] == 'event') {
                            // The server's own words say "load" and "organization"; a known event
                            // is worded as the banner words it. An unknown one keeps the server's.
                            final plain = noticeWords(
                                message['eventKey']?.toString() ?? '',
                                forShipper:
                                    AuthorizationSession.hasRole('SHIPPER'));
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Card(
                                color: const Color(0xFFEAF1F8),
                                child: ListTile(
                                  leading: const Icon(
                                      Icons.notifications_active_outlined,
                                      color: _navy),
                                  title: Text(
                                      plain ??
                                          message['title']?.toString() ??
                                          'Shipment update',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  subtitle: plain != null
                                      ? null
                                      : Text(message['body']?.toString() ??
                                          'There is an update for this shipment.'),
                                ),
                              ),
                            );
                          }
                          final mine = message['senderUserId'] ==
                              AuthorizationSession.user?['id'];
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Card(
                              color:
                                  mine ? _navy.withOpacity(.08) : Colors.white,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * .78),
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              mine
                                                  ? 'You'
                                                  : 'Shipment participant',
                                              style: const TextStyle(
                                                  fontSize: 12, color: _muted)),
                                          const SizedBox(height: 4),
                                          SelectableText(
                                              message['body']?.toString() ??
                                                  ''),
                                        ])),
                              ),
                            ),
                          );
                        },
                      ))),
          if (_canSend)
            SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                            child: TextField(
                                controller: _composer,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: 4000,
                                onChanged: _onChanged,
                                decoration: const InputDecoration(
                                    hintText: 'Write a message',
                                    border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            onPressed: _sending ? null : _send,
                            tooltip: 'Send message',
                            icon: _sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.send)),
                      ]),
                )),
        ]),
      );
}
