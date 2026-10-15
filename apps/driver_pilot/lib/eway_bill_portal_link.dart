import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'eway_bill_error_text.dart';

const governmentPortalAddress = 'https://ewaybillgst.gov.in';

/// The real portal, unless the build points at the practice site: --dart-define=EWAY_PORTAL=http://.../demo/eway-portal
const ewayBillPortalAddress = String.fromEnvironment('EWAY_PORTAL',
    defaultValue: governmentPortalAddress);

/// Says "government" only when [address] really is the government site.
String portalNameFor(String address) => address == governmentPortalAddress
    ? 'government portal'
    : 'practice portal';

String portalButtonLabelFor(String address) =>
    address == governmentPortalAddress
        ? 'Open the government e-way bill portal'
        : 'Open the practice e-way bill portal';

/// Names the address the browser was asked to open.
String portalOpenFailedSentenceFor(String address) {
  // Authority, not host: the practice site's port is part of its address.
  final host = Uri.tryParse(address)?.authority ?? '';
  return 'Could not open the portal from here. Its address is ${host.isEmpty ? address : host}.';
}

/// "government portal" or "practice portal", for the portal this build opens.
String get ewayBillPortalName => portalNameFor(ewayBillPortalAddress);

/// The link-out button to the portal this build opens, with its own line for when the browser would not open.
class EwayBillPortalButton extends StatefulWidget {
  const EwayBillPortalButton({super.key});

  @override
  State<EwayBillPortalButton> createState() => _EwayBillPortalButtonState();
}

class _EwayBillPortalButtonState extends State<EwayBillPortalButton> {
  String? _error;

  Future<void> _openPortal() async {
    setState(() => _error = null);
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(ewayBillPortalAddress),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      setState(
          () => _error = portalOpenFailedSentenceFor(ewayBillPortalAddress));
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: _openPortal,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(portalButtonLabelFor(ewayBillPortalAddress)))),
        EwayBillErrorText(_error),
      ]);
}
