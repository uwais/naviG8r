import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../customer_session.dart";
import "../driver_theme.dart";
import "../pilot_api.dart";
import "../plain_error_sentence.dart";
import "shipper_scaffold.dart";

class CustomerIntegrationsScreen extends StatefulWidget {
  const CustomerIntegrationsScreen({super.key});

  @override
  State<CustomerIntegrationsScreen> createState() =>
      _CustomerIntegrationsScreenState();
}

class _CustomerIntegrationsScreenState
    extends State<CustomerIntegrationsScreen> {
  final _webhookUrl = TextEditingController();
  bool _loading = false;
  bool _saving = false;
  bool _creatingKey = false;
  bool _testingWebhook = false;
  String? _error;
  Map<String, dynamic>? _connection;
  List<Map<String, dynamic>> _apiKeys = [];
  List<Map<String, dynamic>> _deliveries = [];
  String _paymentPolicy = "portal_checkout";

  static const _paymentPolicyLabels = {
    "portal_checkout": "Portal checkout (Razorpay in customer web)",
    "erp_preauthorized": "ERP pre-authorized (book without portal checkout)",
  };

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _webhookUrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await CustomerSession.refresh();
    if (!mounted) return;
    if (!CustomerSession.isSignedIn) {
      context.go("/customer/login");
      return;
    }
    if (!CustomerSession.canManageIntegrations) {
      setState(() => _error = "Only company admins can manage ERP integrations.");
      return;
    }
    await _load();
  }

  String get _orgQuery {
    final orgId = CustomerSession.customerOrgId;
    return orgId != null && orgId.isNotEmpty ? "?orgId=$orgId" : "";
  }

  Future<void> _load() async {
    if (_orgQuery.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api.get<Map<String, dynamic>>(
          "/v1/pilot/customer/integrations$_orgQuery");
      final conn = r.data?["connection"];
      if (conn is Map<String, dynamic>) {
        _connection = conn;
        _webhookUrl.text = conn["webhookUrl"]?.toString() ?? "";
        _paymentPolicy = conn["paymentPolicy"]?.toString() ?? "portal_checkout";
      }
      _apiKeys = _mapList(r.data?["apiKeys"]);
      _deliveries = _mapList(r.data?["recentDeliveries"]);
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not load the integration settings. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _mapList(Object? raw) {
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) list.add(item);
      }
    }
    return list;
  }

  Future<void> _saveConnection({bool regenerateWebhookSecret = false}) async {
    if (_orgQuery.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await api.patch<Map<String, dynamic>>(
        "/v1/pilot/customer/integrations/connection$_orgQuery",
        data: {
          "webhookUrl": _webhookUrl.text.trim(),
          "paymentPolicy": _paymentPolicy,
          "regenerateWebhookSecret": regenerateWebhookSecret,
        },
      );
      final conn = r.data?["connection"];
      if (conn is Map<String, dynamic>) {
        _connection = conn;
        if (regenerateWebhookSecret && conn["webhookSecret"] != null) {
          await _showSecretDialog(
            title: "Webhook secret (copy now)",
            secret: conn["webhookSecret"]?.toString() ?? "",
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Integration settings saved.")));
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not save the settings. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createApiKey() async {
    if (_orgQuery.isEmpty) return;
    setState(() {
      _creatingKey = true;
      _error = null;
    });
    try {
      final r = await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/integrations/keys$_orgQuery",
        data: {
          "scopes": ["loads:read", "loads:write", "webhooks:manage"]
        },
      );
      final token = r.data?["token"]?.toString() ?? "";
      if (token.isNotEmpty) {
        await _showSecretDialog(title: "API token (shown once)", secret: token);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not create a key. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _creatingKey = false);
    }
  }

  Future<void> _revokeKey(String keyId) async {
    if (_orgQuery.isEmpty || keyId.isEmpty) return;
    setState(() => _error = null);
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/integrations/keys/revoke$_orgQuery",
        data: {"keyId": keyId},
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("API key revoked.")));
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not revoke this key. Check your connection, then try again."));
      }
    }
  }

  Future<void> _testWebhook() async {
    if (_orgQuery.isEmpty) return;
    setState(() {
      _testingWebhook = true;
      _error = null;
    });
    try {
      final r = await api.post<Map<String, dynamic>>(
          "/v1/pilot/customer/integrations/webhooks/test$_orgQuery");
      final ok = r.data?["ok"] == true;
      final status = r.data?["httpStatus"];
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ok
                ? "Test webhook delivered (HTTP $status)."
                : "Test webhook failed (HTTP $status).")),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not send the test webhook. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _testingWebhook = false);
    }
  }

  Future<void> _retryDelivery(String deliveryId) async {
    if (_orgQuery.isEmpty) return;
    try {
      await api.post<Map<String, dynamic>>(
          "/v1/pilot/customer/integrations/deliveries/$deliveryId/retry$_orgQuery");
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Sending it again.")));
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not resend this call. Check your connection, then try again."));
      }
    }
  }

  Future<void> _showSecretDialog(
      {required String title, required String secret}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SelectableText(secret,
            style: const TextStyle(fontFamily: "monospace", fontSize: 12)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Done"))
        ],
      ),
    );
  }

  String _deliveryStatusLabel(String? status) {
    switch (status) {
      case "DELIVERED":
        return "Delivered";
      case "DEAD":
        return "Failed. No more automatic tries";
      case "PENDING":
      default:
        return "Waiting to send";
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasWebhookSecret = _connection?["hasWebhookSecret"] == true;

    return CustomerScaffold(
      title: "Integrations",
      currentPath: "/customer/integrations",
      bodyBuilder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            CustomerSession.customerOrgName ?? "Your company",
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: DriverTheme.navy,
                fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            "Connect your ERP. It can then create shipments by itself and get carrier, tracking and payment updates by webhook.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          const Text(
            "See docs/erp-integration.md in the NaviG8r repo for field mapping and authentication details.",
            style:
                TextStyle(fontSize: 12, color: DriverTheme.muted, height: 1.35),
          ),
          if (!CustomerSession.canManageIntegrations) ...[
            const SizedBox(height: 12),
            Text(_error ?? "Only company admins can use this page.",
                style: const TextStyle(color: Colors.red)),
          ] else ...[
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator())),
            if (!_loading) ...[
              const SizedBox(height: 16),
              const Text("Webhook callback",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _webhookUrl,
                decoration: const InputDecoration(
                  labelText: "HTTPS callback URL",
                  hintText: "https://erp.example.com/navig8r/webhook",
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _paymentPolicy,
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Payment policy"),
                // The open menu shows each choice in full, wrapping if it must;
                // the closed field keeps the chosen one to a single line.
                selectedItemBuilder: (_) => [
                  for (final label in _paymentPolicyLabels.values)
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                items: [
                  for (final policy in _paymentPolicyLabels.entries)
                    DropdownMenuItem(
                        value: policy.key, child: Text(policy.value)),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _paymentPolicy = v);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _saveConnection(),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text("Save settings"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () =>
                              _saveConnection(regenerateWebhookSecret: true),
                      child: const Text("Make a new secret"),
                    ),
                  ),
                ],
              ),
              if (hasWebhookSecret)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                      "A webhook secret is set. To see a new one, tap Make a new secret.",
                      style: TextStyle(fontSize: 11, color: DriverTheme.muted)),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _testingWebhook || _webhookUrl.text.trim().isEmpty
                    ? null
                    : _testWebhook,
                icon: _testingWebhook
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined, size: 18),
                label: const Text("Send a test webhook"),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Text("API keys",
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  FilledButton.tonal(
                    onPressed: _creatingKey ? null : _createApiKey,
                    child: _creatingKey
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text("Create key"),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                "Use Bearer nvg8r_{keyId}_{secret} or X-Api-Key + X-Api-Secret headers. You see the full token only once, when you create it.",
                style: TextStyle(
                    fontSize: 12, color: DriverTheme.muted, height: 1.35),
              ),
              ..._apiKeys.map((k) {
                final keyId = k["keyId"]?.toString() ?? "—";
                final scopes = (k["scopes"] as List?)
                        ?.map((s) => s.toString())
                        .join(", ") ??
                    "";
                return Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    title: Text(keyId,
                        style: const TextStyle(
                            fontFamily: "monospace", fontSize: 13)),
                    subtitle: Text(scopes.isEmpty ? "—" : scopes),
                    trailing: IconButton(
                      tooltip: "Revoke",
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _revokeKey(keyId),
                    ),
                  ),
                );
              }),
              if (_apiKeys.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text("No API keys yet.",
                      style: TextStyle(color: DriverTheme.muted)),
                ),
              const SizedBox(height: 24),
              const Text("Recent webhook calls",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              ..._deliveries.map((d) {
                final id = d["id"]?.toString() ?? "";
                final status = d["status"]?.toString();
                final attempts = d["attempts"];
                final httpStatus = d["lastHttpStatus"];
                final eventId = d["eventId"]?.toString() ?? "";
                return Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    title: Text(eventId, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      "${_deliveryStatusLabel(status)} · attempts: $attempts · HTTP: ${httpStatus ?? "—"}",
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: status != "DELIVERED"
                        ? TextButton(
                            onPressed:
                                id.isEmpty ? null : () => _retryDelivery(id),
                            child: const Text("Retry"))
                        : null,
                  ),
                );
              }),
              if (_deliveries.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text("No webhook calls yet.",
                      style: TextStyle(color: DriverTheme.muted)),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
