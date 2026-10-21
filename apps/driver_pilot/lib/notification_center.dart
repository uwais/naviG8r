// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'authorization_session.dart';
import 'conversation_drafts.dart';
import 'shipper/shipper_words.dart';
import 'pilot_api.dart';
import 'plain_error_sentence.dart';
import 'push_notifications.dart';
import 'signed_in_header.dart';
import 'ui/format.dart';
import 'ui/nv_button.dart';
import 'ui/nv_list_card.dart';
import 'ui/tokens.dart';

const _navy = Color(0xFF122C53);
const _background = Color(0xFFF4F7FA);
const _muted = Color(0xFF64748B);

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

/// The banner's words for the newest notice, by what happened and to whom. The server's own titles
/// say "load" and "organization", so the app words them itself.
String noticeWords(String eventKey, {required bool forShipper}) {
  if (forShipper) {
    return switch (eventKey) {
      'shipment.booked' => 'Your booking is made.',
      'shipment.carrier_accepted' => 'The carrier accepted your booking.',
      'trip.started' => 'Your goods are on the way.',
      'trip.completed' => 'The trip is complete.',
      'shipment.pod_submitted' => 'The carrier confirmed delivery.',
      'shipment.pod_accepted' => 'Delivery accepted.',
      'payment.status_changed' => 'Your payment was updated.',
      'conversation.message' => 'New message on a shipment.',
      _ => 'New update on a shipment.',
    };
  }
  return switch (eventKey) {
    'shipment.booked' => 'New booking from a shipper.',
    'shipment.carrier_accepted' => 'Booking accepted.',
    'trip.started' => 'Trip started.',
    'trip.completed' => 'Trip complete.',
    'shipment.pod_submitted' => 'Delivery confirmed.',
    'shipment.pod_accepted' => 'The shipper accepted the delivery.',
    'payment.status_changed' => 'A payment was updated.',
    'conversation.message' => 'New message on a booking.',
    _ => 'New update on a booking.',
  };
}

/// One check for the whole app, however many headers show a bell: every 15 s while any bell is
/// on screen, and none once the last bell goes. When the unread count goes up, the newest bell
/// shows a short banner for the newest notice.
class NotificationWatch {
  NotificationWatch._();

  static const interval = Duration(seconds: 15);
  static const bannerTime = Duration(seconds: 6);
  static final unread = ValueNotifier<int>(0);
  static final _bells = <_NotificationBellState>[];
  static Timer? _poll;
  static Timer? _bannerTimer;
  // Null until the first answer for this person and company, so opening the app or switching
  // company shows no banner for notices that were already there.
  static int? _lastCount;
  static String? _lastScope;

  static void _add(_NotificationBellState bell) {
    _bells.add(bell);
    if (_poll != null) return;
    check();
    _poll = Timer.periodic(interval, (_) => check());
  }

  static void _remove(_NotificationBellState bell) {
    _bells.remove(bell);
    if (_bells.isNotEmpty) return;
    _poll?.cancel();
    _poll = null;
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _lastCount = null;
  }

  /// Asks for the unread count and the newest notice. A failed check keeps the count shown.
  static Future<void> check() async {
    final scope =
        '${AuthorizationSession.identityGeneration}:${AuthorizationSession.scopeKey}';
    final Map<String, dynamic>? data;
    try {
      data = (await api.get<Map<String, dynamic>>('/v1/notifications',
              query: {'limit': '1'}))
          .data;
    } catch (_) {
      return;
    }
    if (scope !=
        '${AuthorizationSession.identityGeneration}:${AuthorizationSession.scopeKey}') {
      return;
    }
    final count = (data?['unreadCount'] as num?)?.toInt() ?? 0;
    final previous = _lastScope == scope ? _lastCount : null;
    _lastScope = scope;
    _lastCount = count;
    unread.value = count;
    final raw = data?['notifications'];
    final newest =
        raw is List && raw.isNotEmpty && raw.first is Map<String, dynamic>
            ? raw.first as Map<String, dynamic>
            : null;
    if (previous != null && count > previous && newest != null) {
      _announce(newest);
    }
  }

  static void _announce(Map<String, dynamic> notice) {
    final eventKey = notice['eventKey']?.toString() ?? '';
    final shipmentId = notice['shipmentId']?.toString() ?? '';
    // The server never sends a driver a payment notice; this keeps it so if that ever changes.
    final isDriver = AuthorizationSession.principal?['subrole'] == 'DRIVER';
    if (isDriver && eventKey.startsWith('payment.')) return;
    if (_bells.isEmpty || shipmentId.isEmpty) return;
    _bells.last._showBanner(
        noticeWords(eventKey,
            forShipper: AuthorizationSession.hasRole('SHIPPER')),
        shipmentId);
  }
}

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  @override
  void initState() {
    super.initState();
    NotificationWatch._add(this);
  }

  @override
  void dispose() {
    NotificationWatch._remove(this);
    super.dispose();
  }

  void _openShipment(String shipmentId) {
    final router = GoRouter.maybeOf(context);
    final id = Uri.encodeComponent(shipmentId);
    if (router == null) {
      openShipmentConversation(context, shipmentId);
    } else if (AuthorizationSession.hasRole('SHIPPER')) {
      router.go('/customer/shipments/$id');
    } else {
      router.go('/driver/shipment/$id');
    }
  }

  /// A live region, so a screen reader reads it once as it appears. It stays until closed when a
  /// screen reader is on, so there is time to reach View.
  void _showBanner(String words, String shipmentId) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(MaterialBanner(
      content: Text(words, style: NvText.bodyStrong),
      backgroundColor: NvColors.card,
      leading: const Icon(Icons.notifications_active_outlined,
          color: NvColors.navyInk),
      actions: [
        TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('Close')),
        TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              _openShipment(shipmentId);
            },
            child: const Text('View')),
      ],
    ));
    NotificationWatch._bannerTimer?.cancel();
    NotificationWatch._bannerTimer = MediaQuery.accessibleNavigationOf(context)
        ? null
        : Timer(NotificationWatch.bannerTime, messenger.hideCurrentMaterialBanner);
  }

  Future<void> _openInbox() async {
    await openNotificationInbox(context);
    // Reading updates there lowers the count; show it now rather than at the next check.
    NotificationWatch.check();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: NotificationWatch.unread,
        builder: (context, unread, _) => IconButton(
          tooltip:
              unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
          onPressed: _openInbox,
          color: NvColors.navyInk,
          icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_outlined)),
        ),
      );
}

/// "Updates" (sh-notifications): one row per shipment with new activity, named by its route and
/// date. A row from the server holds no event words, so each says how many updates are new.
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
  bool _failed = false;
  String? _nextCursor;
  Timer? _poll;

  /// A shipper's own shipments and their lanes, to name each row. Other logins see no names.
  Map<String, Map<String, dynamic>> _shipmentsById = {};
  Map<String, Map<String, dynamic>> _lanesById = {};

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
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadNames() async {
    if (!AuthorizationSession.hasRole('SHIPPER') ||
        !AuthorizationSession.can('load.read')) {
      return;
    }
    final lanes = loadLanesById();
    try {
      final response = await api.get<Map<String, dynamic>>('/shipments');
      final raw = response.data?['shipments'];
      final lanesById = await lanes;
      if (!mounted) return;
      setState(() {
        _shipmentsById = {
          if (raw is List)
            for (final shipment in raw.whereType<Map<String, dynamic>>())
              if (shipment['id'] != null) shipment['id'].toString(): shipment,
        };
        _lanesById = lanesById;
      });
    } catch (_) {
      // Rows keep their plain title; the updates themselves still load.
      await lanes;
    }
  }

  Future<void> _enablePushAlerts() async {
    final continueSetup = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Shipment alerts'),
        content: const Text(
            'Get alerts on this device when something new happens on your shipments. Alerts do not show message text or shipment details.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (continueSetup != true || !mounted) return;
    final enabled = await PushNotifications.instance.enableAlerts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(enabled
          ? 'Shipment alerts are enabled on this device.'
          : 'Alerts were not enabled. Check that notifications are allowed for this app in Android settings.'),
    ));
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
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loadingEarlier = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadNames();
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

  int _unreadOf(Map<String, dynamic> item) =>
      (item['unreadCount'] as num?)?.toInt() ?? 0;

  Widget _row(Map<String, dynamic> item) {
    final shipment = _shipmentsById[item['shipmentId']?.toString()];
    final name = shipment == null
        ? null
        : shipmentRouteName(shipment,
            lane: laneOfShipment(shipment, _lanesById));
    final unread = _unreadOf(item);
    final latest = item['latestAtUtcMs'];
    final when = latest is num
        ? DateTime.fromMillisecondsSinceEpoch(latest.toInt(), isUtc: true)
        : null;
    return MergeSemantics(
      child: InkWell(
        onTap: () => _open(item),
        highlightColor: NvColors.sunken,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: NvSpace.targetMin),
          child: Padding(
            padding: const EdgeInsets.all(NvSpace.s4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // The dot marks a new update; the words under the title say it too.
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: 7, right: NvSpace.s3),
                  child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: unread > 0 ? NvColors.navy : null,
                          shape: BoxShape.circle)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name ?? 'Shipment update',
                        style: NvText.bodyStrong
                            .copyWith(color: NvColors.navyInk)),
                    Text(
                        switch (unread) {
                          0 => 'No unread updates',
                          1 => 'New update',
                          _ => '$unread new updates',
                        },
                        style: NvText.body),
                    if (when != null)
                      Text('${formatDate(when)}, ${formatTimeIst(when)}',
                          style: NvText.caption),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _group(String label, List<Map<String, dynamic>> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: NvSpace.s4),
          Semantics(header: true, child: Text(label, style: NvText.label)),
          const SizedBox(height: NvSpace.s2),
          Material(
            color: NvColors.card,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NvRadius.card),
                side: const BorderSide(color: NvColors.line)),
            child: Column(children: [
              for (final (index, item) in items.indexed) ...[
                if (index > 0) const Divider(height: 1, color: NvColors.line),
                _row(item),
              ],
            ]),
          ),
        ],
      );

  List<Widget> _body() {
    if (_loading) {
      return const [SizedBox(height: NvSpace.s4), NvListLoadingCard()];
    }
    if (_failed && _items.isEmpty) {
      return [
        const SizedBox(height: NvSpace.s4),
        NvListError(
            title: 'Could not load updates.',
            help: 'Check your connection, then try again.',
            onRetry: () {
              setState(() => _loading = true);
              _load();
            }),
      ];
    }
    if (_items.isEmpty) {
      return const [
        SizedBox(height: NvSpace.s4),
        NvListEmpty(title: 'You’re all caught up.'),
      ];
    }
    final fresh = _items.where((item) => _unreadOf(item) > 0).toList();
    final earlier = _items.where((item) => _unreadOf(item) == 0).toList();
    return [
      if (fresh.isNotEmpty) _group('NEW', fresh),
      if (earlier.isNotEmpty) _group('EARLIER', earlier),
      if (_failed) ...[
        const SizedBox(height: NvSpace.s3),
        const Text(
            'Could not load updates. Check your connection, then try again.',
            style: NvText.caption),
      ],
      if (_nextCursor != null) ...[
        const SizedBox(height: NvSpace.s3),
        NvButton(
            label: 'Load earlier notifications',
            kind: NvButtonKind.quiet,
            loading: _loadingEarlier,
            fullWidth: true,
            onPressed: _loadEarlier),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: NvColors.page,
        appBar: signedInHeader(context,
            backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                NvSpace.gutter, NvSpace.s4, NvSpace.gutter, NvSpace.s6),
            children: [
              Semantics(
                  header: true,
                  child: const Text('Updates', style: NvText.title)),
              ..._body(),
              if (PushNotifications.instance.available) ...[
                const SizedBox(height: NvSpace.s4),
                NvButton(
                    label: 'Enable alerts on this device',
                    kind: NvButtonKind.quiet,
                    fullWidth: true,
                    onPressed: _enablePushAlerts),
              ],
            ],
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
