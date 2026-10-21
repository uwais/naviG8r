// The app-wide unread check and the header bell that shows it, with a banner for a new notice.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_in_background.dart';
import 'authorization_session.dart';
import 'notice_words.dart';
import 'notification_center.dart';
import 'organization_access.dart';
import 'pilot_api.dart';
import 'shipment_conversation.dart';
import 'ui/tokens.dart';

/// One check for the whole app, however many headers show a bell: every 30 s while any bell is
/// on screen and the app is in front, and none once the last bell goes. When the unread count
/// goes up, the newest bell shows a short banner for the newest notice.
class NotificationWatch {
  NotificationWatch._();

  static const interval = Duration(seconds: 30);
  static const bannerTime = Duration(seconds: 6);
  static final unread = ValueNotifier<int>(0);
  static final _bells = <_NotificationBellState>[];
  static Timer? _poll;
  static AppLifecycleListener? _lifecycle;
  static Timer? _bannerTimer;
  static ScaffoldMessengerState? _bannerMessenger;
  // Each check's number. Answers can arrive out of order; only the newest check's is used.
  static int _newestCheck = 0;
  // Null until the first answer for this person and company, so opening the app or switching
  // company shows no banner for notices that were already there.
  static int? _lastCount;
  static String? _lastScope;

  static void _add(_NotificationBellState bell) {
    _bells.add(bell);
    if (_poll != null) return;
    check();
    _poll = Timer.periodic(interval, (_) {
      if (!appIsInBackground) check();
    });
    _lifecycle = AppLifecycleListener(onShow: check);
  }

  static void _remove(_NotificationBellState bell) {
    _bells.remove(bell);
    if (_bells.isNotEmpty) return;
    _poll?.cancel();
    _poll = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _lastCount = null;
    // A check still on its way was for the person who has gone.
    _newestCheck++;
    // The bell goes while the tree is taken down, when nothing may rebuild: after this frame, then.
    scheduleMicrotask(() {
      if (_bells.isNotEmpty) return;
      final messenger = _bannerMessenger;
      _bannerMessenger = null;
      if (messenger != null && messenger.mounted) {
        messenger.hideCurrentMaterialBanner();
      }
      unread.value = 0;
    });
  }

  /// Asks for the unread count and the newest notice. A failed check keeps the count shown.
  static Future<void> check() async {
    final number = ++_newestCheck;
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
    if (number != _newestCheck ||
        scope !=
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
    final forShipper = AuthorizationSession.hasRole('SHIPPER');
    // A carrier's payment amounts are the owner's, as on Earnings: no payment banner for a
    // driver or a dispatcher. The server sends a driver none; this keeps it so if that changes.
    if (eventKey.startsWith('payment.') &&
        !forShipper &&
        !carrierSeesPaymentAmounts()) {
      return;
    }
    final bell = _newestMountedBell();
    if (bell == null || shipmentId.isEmpty) return;
    bell._showBanner(
        noticeWords(eventKey, forShipper: forShipper) ??
            (forShipper
                ? 'New update on a shipment.'
                : 'New update on a booking.'),
        shipmentId);
  }

  static _NotificationBellState? _newestMountedBell() {
    for (final bell in _bells.reversed) {
      if (bell.mounted) return bell;
    }
    return null;
  }

  /// From the bell on screen when View is tapped: the one that showed the banner may have gone.
  static void _openShipment(String shipmentId) {
    final bell = _newestMountedBell();
    if (bell == null) return;
    final context = bell.context;
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

  /// A live region, so a screen reader reads it once as it appears. It stays until closed when a
  /// screen reader is on, so there is time to reach View.
  void _showBanner(String words, String shipmentId) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    void hide() {
      if (messenger.mounted) messenger.hideCurrentMaterialBanner();
    }

    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(MaterialBanner(
      content: Text(words, style: NvText.bodyStrong),
      backgroundColor: NvColors.card,
      leading: const Icon(Icons.notifications_active_outlined,
          color: NvColors.navyInk),
      actions: [
        TextButton(onPressed: hide, child: const Text('Close')),
        TextButton(
            onPressed: () {
              hide();
              NotificationWatch._openShipment(shipmentId);
            },
            child: const Text('View')),
      ],
    ));
    NotificationWatch._bannerMessenger = messenger;
    NotificationWatch._bannerTimer?.cancel();
    NotificationWatch._bannerTimer = MediaQuery.accessibleNavigationOf(context)
        ? null
        : Timer(NotificationWatch.bannerTime, hide);
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
              unread > 0 ? 'Updates, $unread new' : 'Updates',
          onPressed: _openInbox,
          color: NvColors.navyInk,
          icon: Badge(
              isLabelVisible: unread > 0,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: const Icon(Icons.notifications_outlined)),
        ),
      );
}
