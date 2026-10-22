// The Updates inbox: one row per shipment with new activity, and one per new trip for a driver.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_in_background.dart';
import 'authorization_session.dart';
import 'shipper/shipper_words.dart';
import 'pilot_api.dart';
import 'push_notifications.dart';
import 'shipment_conversation.dart';
import 'signed_in_header.dart';
import 'ui/format.dart';
import 'ui/nv_button.dart';
import 'ui/nv_list_card.dart';
import 'ui/tokens.dart';

Future<void> openNotificationInbox(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationInboxScreen()),
    );

/// A driver's new-trip notice has no shipment to open: it is marked read, and its trip opens.
Future<void> openTripNotice(BuildContext context,
    {required String notificationId, required String tripId}) async {
  final router = GoRouter.maybeOf(context);
  // Updates is pushed over the router's pages, on the root navigator; the trip opens as a page under the
  // shell, so screens pushed like that are closed first or the trip opens behind them.
  final navigators = {
    Navigator.of(context),
    Navigator.of(context, rootNavigator: true)
  };
  if (notificationId.isNotEmpty) {
    try {
      await api.patch(
          '/v1/notifications/${Uri.encodeComponent(notificationId)}/read');
    } catch (_) {
      // The trip still opens; the notice stays new until the next try.
    }
  }
  if (router == null) return;
  for (final navigator in navigators) {
    if (navigator.mounted) {
      navigator.popUntil((route) => route.settings is Page);
    }
  }
  router.go('/driver/trip/${Uri.encodeComponent(tripId)}/active');
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
  // True while a timed check is out, so coming back to the app just before a tick sends one, not two.
  bool _checkingQuietly = false;
  late final AppLifecycleListener _lifecycle;

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
            'Get alerts on this phone when something new happens on your shipments. Alerts do not show message text or shipment details.'),
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
          ? 'Alerts are on for this phone.'
          : 'Alerts are not on. In Android settings, allow notifications for this app.'),
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
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!appIsInBackground) _checkQuietly();
    });
    _lifecycle = AppLifecycleListener(onShow: _checkQuietly);
  }

  Future<void> _checkQuietly() async {
    if (_checkingQuietly) return;
    _checkingQuietly = true;
    try {
      await _load();
    } finally {
      _checkingQuietly = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final tripId = item['tripId']?.toString() ?? '';
    final shipmentId = item['shipmentId']?.toString() ?? '';
    if (tripId.isNotEmpty) {
      await openTripNotice(context,
          notificationId: item['notificationId']?.toString() ?? '',
          tripId: tripId);
    } else if (shipmentId.isNotEmpty) {
      await openShipmentConversation(context, shipmentId);
    }
    if (mounted) _load();
  }

  int _unreadOf(Map<String, dynamic> item) =>
      (item['unreadCount'] as num?)?.toInt() ?? 0;

  Widget _row(Map<String, dynamic> item) {
    final shipment = _shipmentsById[item['shipmentId']?.toString()];
    // A driver's new-trip row is named by the trip's route, which the server sends with it.
    final isTrip = (item['tripId']?.toString() ?? '').isNotEmpty;
    final name = isTrip
        ? item['tripRoute']?.toString()
        : shipment == null
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
                    Text(name ?? (isTrip ? 'New trip' : 'Shipment update'),
                        style: NvText.bodyStrong
                            .copyWith(color: NvColors.navyInk)),
                    Text(
                        switch (unread) {
                          0 => 'No unread updates',
                          _ when isTrip => 'You have a new trip.',
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
        NvListEmpty(title: 'No new updates.'),
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
            label: 'Show earlier updates',
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
                    label: 'Turn on alerts on this phone',
                    kind: NvButtonKind.quiet,
                    fullWidth: true,
                    onPressed: _enablePushAlerts),
              ],
            ],
          ),
        ),
      );
}
