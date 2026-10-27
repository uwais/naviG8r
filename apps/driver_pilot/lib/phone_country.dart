import "package:flutter/material.dart";

const supportedCountryCodes = <String>["+91", "+1"];

String phoneIdentityKey(String countryCode, String phone) =>
    "$countryCode:${_digitsOnly(phone)}";

String _digitsOnly(String value) => value.replaceAll(RegExp(r"[^0-9]"), "");

class CountryCodeField extends StatelessWidget {
  const CountryCodeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: supportedCountryCodes.contains(value) ? value : "+91",
      isExpanded: true,
      decoration: const InputDecoration(labelText: "Code"),
      selectedItemBuilder: (_) => const [Text("+91"), Text("+1")],
      items: const [
        DropdownMenuItem(value: "+91", child: Text("India (+91)")),
        DropdownMenuItem(value: "+1", child: Text("United States (+1)")),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    required this.countryCode,
    required this.onCountryChanged,
    this.onChanged,
    this.label = "Phone number",
    this.hintText,
  });

  final TextEditingController controller;
  final String countryCode;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String>? onChanged;
  final String label;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: CountryCodeField(
            value: countryCode,
            onChanged: onCountryChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            onChanged: onChanged,
            decoration: InputDecoration(labelText: label, hintText: hintText),
          ),
        ),
      ],
    );
  }
}
