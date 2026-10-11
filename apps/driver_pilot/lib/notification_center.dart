// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'conversation_drafts.dart';
import 'pilot_api.dart';

const _navy = Color(0xFF122C53);
const _background = Color(0xFFF4F7FA);
const _muted = Color(0xFF64748B);

String _activityDate(Object? value) {
  final millis = (value as num?)?.toInt();
  if (millis == null) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final suffix = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.month}/${date.day} $hour:$minute $suffix';
}

String _newClientRequestId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';

Future<void> openNotificationInbox(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationInboxScreen()),
    );

Future<void> openShipmentConversation(
        BuildContext context, String shipmentId) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShipmentConversationScreen(shipmentId: shipmentId),
    ));

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;
  Timer? _poll;

  Future<void> _refresh() async {
    try {
      final result =
          await api.get<Map<String, dynamic>>('/v1/notifications/shipments');
      if (mounted) {
        setState(() =>
            _unread = (result.data?['unreadCount'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {
      if (mounted) setState(() => _unread = 0);
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip:
            _unread > 0 ? 'Notifications, $_unread unread' : 'Notifications',
        onPressed: () => openNotificationInbox(context),
        icon: Badge(
            isLabelVisible: _unread > 0,
            label: Text(_unread > 99 ? '99+' : '$_unread'),
            child: const Icon(Icons.notifications_outlined)),
      );
}

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _loadingEarlier = false;
  String? _error;
  String? _nextCursor;
  int _unread = 0;
  Timer? _poll;

  Future<void> _load() async {
    try {
      final response =
          await api.get<Map<String, dynamic>>('/v1/notifications/shipments');
      if (!mounted) return;
      final raw = response.data?['shipments'];
      setState(() {
        _items =
            raw is List ? raw.whereType<Map<String, dynamic>>().toList() : [];
        _nextCursor = response.data?['nextBefore']?.toString();
        _unread = (response.data?['unreadCount'] as num?)?.toInt() ?? 0;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = formatApiError(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadEarlier() async {
    final cursor = _nextCursor;
    if (cursor == null || _loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    try {
      final response = await api.get<Map<String, dynamic>>(
        '/v1/notifications/shipments',
        query: {'before': cursor},
      );
      if (!mounted) return;
      final raw = response.data?['shipments'];
      final older = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _items = [..._items, ...older];
        _nextCursor = response.data?['nextBefore']?.toString();
        _unread = (response.data?['unreadCount'] as num?)?.toInt() ?? _unread;
      });
    } catch (error) {
      if (mounted) setState(() => _error = formatApiError(error));
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final shipmentId = item['shipmentId']?.toString() ?? '';
    if (shipmentId.isNotEmpty) {
      await openShipmentConversation(context, shipmentId);
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        appBar: AppBar(title: const Text('Notifications'), actions: [
          if (_unread > 0)
            Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text('$_unread unread'))),
        ]),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? ListView(children: const [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator())
                ])
              : _error != null
                  ? ListView(children: [
                      Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_error!))
                    ])
                  : _items.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 70),
                          Center(child: Text('You’re all caught up.'))
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount:
                              _items.length + (_nextCursor == null ? 0 : 1),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            if (index == _items.length) {
                              return TextButton.icon(
                                onPressed:
                                    _loadingEarlier ? null : _loadEarlier,
                                icon: _loadingEarlier
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.history),
                                label: const Text('Load earlier notifications'),
                              );
                            }
                            final item = _items[index];
                            final unread =
                                ((item['unreadCount'] as num?)?.toInt() ?? 0) >
                                    0;
                            final shipmentId =
                                item['shipmentId']?.toString() ?? '';
                            final reference = item['shipmentReference']
                                    ?.toString() ??
                                (shipmentId.length > 8
                                    ? shipmentId.substring(0, 8).toUpperCase()
                                    : shipmentId.toUpperCase());
                            final unreadCount =
                                (item['unreadCount'] as num?)?.toInt() ?? 0;
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                    unread
                                        ? Icons.markunread_outlined
                                        : Icons.notifications_none,
                                    color: _navy),
                                title: Text('Shipment update',
                                    style: TextStyle(
                                        fontWeight: unread
                                            ? FontWeight.w700
                                            : FontWeight.w500)),
                                subtitle: Text(
                                    '${unreadCount == 0 ? 'No unread updates' : unreadCount == 1 ? 'New update' : '$unreadCount new updates'}\nShipment $reference · ${_activityDate(item['latestAtUtcMs'])}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(item),
                              ),
                            );
                          },
                        ),
        ),
      );
}

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
        _error = formatApiError(error);
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
      if (mounted) setState(() => _error = formatApiError(error));
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
      if (mounted) setState(() => _error = formatApiError(error));
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
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        appBar: AppBar(title: const Text('Shipment conversation')),
        body: Column(children: [
          if (!_canSend && !_loading)
            const MaterialBanner(
                content: Text('This conversation is read-only.'),
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
              label: const Text('Load earlier messages'),
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
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Card(
                                color: const Color(0xFFEAF1F8),
                                child: ListTile(
                                  leading: const Icon(
                                      Icons.notifications_active_outlined,
                                      color: _navy),
                                  title: Text(
                                      message['title']?.toString() ??
                                          'Shipment update',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(message['body']?.toString() ??
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
