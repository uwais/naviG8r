import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../driver_theme.dart";
import "../pilot_api.dart";
import "../plain_error_sentence.dart";
import "shipper_scaffold.dart";

class CustomerRegisterScreen extends StatefulWidget {
  const CustomerRegisterScreen({super.key});

  @override
  State<CustomerRegisterScreen> createState() => _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState extends State<CustomerRegisterScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _org = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": digitsOnly(_phone.text.trim()),
          "orgDisplayName": _org.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Account created. Now sign in with your mobile number.")));
      context.go("/customer/login");
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not register your company. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Register your company",
      currentPath: "/customer/register",
      bodyBuilder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Create your company account. You become its admin and can invite teammates later.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: "Your name")),
          TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: "Mobile number (10 digits)"),
              keyboardType: TextInputType.phone),
          TextField(
              controller: _org,
              decoration:
                  const InputDecoration(labelText: "Company name")),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create account"),
          ),
        ],
      ),
    );
  }
}

class CustomerRegisterUserScreen extends StatefulWidget {
  const CustomerRegisterUserScreen({super.key});

  @override
  State<CustomerRegisterUserScreen> createState() =>
      _CustomerRegisterUserScreenState();
}

class _CustomerRegisterUserScreenState
    extends State<CustomerRegisterUserScreen> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>(
        "/v1/pilot/customer/users/register",
        data: {
          "fullName": _fullName.text.trim(),
          "phone": digitsOnly(_phone.text.trim()),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Account created. Ask your company admin to invite you. Then sign in.")),
      );
      context.go("/customer/login");
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not create your account. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomerScaffold(
      title: "Join your team",
      currentPath: "/customer/register-user",
      bodyBuilder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            "Create your account. Then ask your company admin to invite your phone number.",
            style: TextStyle(color: DriverTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _fullName,
              decoration: const InputDecoration(labelText: "Your name")),
          TextField(
              controller: _phone,
              decoration: const InputDecoration(labelText: "Mobile number (10 digits)"),
              keyboardType: TextInputType.phone),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Create account"),
          ),
        ],
      ),
    );
  }
}
