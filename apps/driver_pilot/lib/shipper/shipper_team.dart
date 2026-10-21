import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../customer_session.dart";
import "../driver_theme.dart";
import "../pilot_api.dart";
import "../plain_error_sentence.dart";
import "../ui/format.dart";
import "shipper_scaffold.dart";

class CustomerTeamScreen extends StatefulWidget {
  const CustomerTeamScreen({super.key});

  @override
  State<CustomerTeamScreen> createState() => _CustomerTeamScreenState();
}

class _CustomerTeamScreenState extends State<CustomerTeamScreen> {
  final _phone = TextEditingController();
  bool _loading = false;
  bool _inviting = false;
  String? _error;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await CustomerSession.refresh();
    if (!mounted) return;
    if (!mounted) return;
    if (!CustomerSession.isSignedIn) {
      context.go("/customer/login");
      return;
    }
    if (!CustomerSession.isOrgAdmin) {
      setState(() => _error = "Only company admins can manage the team.");
      return;
    }
    await _loadMembers();
  }

  Future<void> _loadMembers() async {
    final orgId = CustomerSession.customerOrgId;
    if (orgId == null || orgId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await api
          .get<Map<String, dynamic>>("/v1/pilot/customer/members?orgId=$orgId");
      final raw = r.data?["members"];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) list.add(item);
        }
      }
      setState(() => _members = list);
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not load your team. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite() async {
    final orgId = CustomerSession.customerOrgId;
    if (orgId == null) return;
    setState(() {
      _inviting = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/members/invite",
        data: {"orgId": orgId, "phone": digitsOnly(_phone.text.trim())},
      );
      _phone.clear();
      await _loadMembers();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Teammate invited.")));
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not invite this teammate. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Team",
      currentPath: "/customer/team",
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
            "Invite teammates who have already registered their phone. Once they join, they see all your company's shipments.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          if (!CustomerSession.isOrgAdmin) ...[
            const SizedBox(height: 12),
            Text(_error ?? "Only company admins can use this page.",
                style: const TextStyle(color: Colors.red)),
          ] else ...[
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: "Teammate's mobile number (10 digits)"),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _inviting ? null : _invite,
              child: _inviting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Invite to company"),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            const Text("Your team",
                style: TextStyle(fontWeight: FontWeight.w600)),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator()),
            ..._members.map((row) {
              final user = row["user"];
              final membership = row["membership"];
              if (user is! Map<String, dynamic>) return const SizedBox.shrink();
              final role = membership is Map<String, dynamic>
                  ? membership["role"]?.toString() ?? ""
                  : "";
              return Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  title: Text(user["fullName"]?.toString() ?? "—"),
                  subtitle: Text(
                      "${formatPhone(user["phone"]?.toString() ?? "")} · ${customerMemberRoleLabel(role)}"),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
