// Load alerts on or off for the signed-in person (Load Board phase 1, 4 Nov 2026). On until they turn it off. Only
// the carrier office gets new-load alerts, so only the office's Company screen shows this.
import "dart:async";

import "package:flutter/material.dart";

import "../pilot_api.dart";
import "../ui/nv_section_card.dart";
import "../ui/tokens.dart";

class LoadAlertsSwitch extends StatefulWidget {
  const LoadAlertsSwitch({super.key});

  @override
  State<LoadAlertsSwitch> createState() => _LoadAlertsSwitchState();
}

class _LoadAlertsSwitchState extends State<LoadAlertsSwitch> {
  bool? _on;
  bool _saving = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  Future<void> _load() async {
    try {
      final r = await api.get<Map<String, dynamic>>("/v1/me/settings");
      final on = r.data?["loadAlerts"];
      if (mounted) {
        setState(() {
          _on = on is bool ? on : true;
          _problem = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _problem = "Could not load this setting.");
    }
  }

  Future<void> _save(bool on) async {
    final before = _on;
    setState(() {
      _on = on;
      _saving = true;
      _problem = null;
    });
    try {
      final r = await api.patch<Map<String, dynamic>>("/v1/me/settings",
          data: {"loadAlerts": on});
      final saved = r.data?["loadAlerts"];
      if (mounted && saved is bool) setState(() => _on = saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _on = before;
          _problem = "Could not save. Check your connection and try again.";
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    return NvSectionCard(
      title: "Load alerts",
      children: [
        const SizedBox(height: NvSpace.s2),
        MergeSemantics(
          child: Row(children: [
            const Expanded(
              child: Text("Tell me when a shipper posts a load.",
                  style: NvText.body),
            ),
            Switch(
              value: on ?? false,
              activeColor: NvColors.card,
              activeTrackColor: NvColors.navy,
              onChanged: on == null || _saving ? null : _save,
            ),
          ]),
        ),
        if (_problem != null) ...[
          const SizedBox(height: NvSpace.s1),
          Semantics(
              liveRegion: true,
              child: Text(_problem!, style: NvText.caption)),
        ],
      ],
    );
  }
}
