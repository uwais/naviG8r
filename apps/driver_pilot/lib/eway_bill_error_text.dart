import 'package:flutter/material.dart';

/// The red sentence under an e-way bill card, form or portal button, or nothing when there is none.
class EwayBillErrorText extends StatelessWidget {
  const EwayBillErrorText(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text,
            style: TextStyle(color: Theme.of(context).colorScheme.error)));
  }
}
