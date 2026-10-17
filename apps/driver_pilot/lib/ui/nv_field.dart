import "package:flutter/material.dart";

import "tokens.dart";

/// A text field with its label always visible above it, and one line under it: the help, or the
/// error in its place. Fixed-option inputs use NvChoiceChips or NvChoiceRows instead.
class NvField extends StatelessWidget {
  const NvField({
    super.key,
    required this.label,
    this.controller,
    this.help,
    this.hint,
    this.unit,
    this.prefix,
    this.optional = false,
    this.errorText,
    this.disabledReason,
    this.readOnly = false,
    this.loadingLabel,
    this.savedMessage,
    this.identifier = false,
    this.keyboardType,
    this.autofillHints,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;

  /// Says the format, such as "Up to 105 kg on this lane."
  final String? help;

  /// Shown inside the empty field, such as "For example 80".
  final String? hint;

  /// Shown at the end of the field, such as "kg".
  final String? unit;

  /// Fixed text at the start of the field that is not typed, such as "+91".
  final String? prefix;

  /// Adds "(optional)" after the label.
  final bool optional;

  /// What is wrong and how to fix it. Replaces the help line and turns the border red.
  final String? errorText;

  /// Disables the field; the reason replaces the help line.
  final String? disabledReason;

  /// For values to copy, not edit, such as the company's own GSTIN.
  final bool readOnly;

  /// Shows a progress ring and these words at the end of the field, such as "Finding places".
  final String? loadingLabel;

  /// A short confirmation that replaces the help line once the value is saved.
  final String? savedMessage;

  /// IDs and numbers people copy (bill numbers, GSTINs) are set in the mono face.
  final bool identifier;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final disabled = disabledReason != null;
    final sunken = disabled || readOnly;
    final valueStyle = identifier
        ? NvText.id.copyWith(fontSize: 16, color: NvColors.ink)
        : NvText.body.copyWith(fontSize: 16, height: 24 / 16);
    final belowField = disabledReason ?? savedMessage ?? help;
    final noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(NvRadius.input),
      borderSide: BorderSide.none,
    );

    // Merged so a screen reader hears the label above, the field and the line under it as one.
    return MergeSemantics(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(text: label, children: [
            if (optional)
              const TextSpan(
                  text: " (optional)",
                  style: TextStyle(
                      fontWeight: FontWeight.w400, color: NvColors.slate)),
          ]),
          style: NvText.bodyStrong,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !disabled,
          readOnly: readOnly,
          keyboardType: keyboardType,
          autofillHints: autofillHints,
          onChanged: onChanged,
          style: valueStyle,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: valueStyle.copyWith(color: NvColors.slate),
            prefixIcon: prefix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(left: 14, right: NvSpace.s2),
                    child: Text(prefix!,
                        style: valueStyle.copyWith(color: NvColors.slate)),
                  ),
            prefixIconConstraints: const BoxConstraints(),
            fillColor: sunken ? NvColors.sunken : NvColors.card,
            enabledBorder: readOnly ? noBorder : null,
            focusedBorder: readOnly ? noBorder : null,
            helperText: belowField,
            helperMaxLines: 6,
            helperStyle: savedMessage != null && !disabled
                ? NvText.caption
                    .copyWith(color: NvColors.good, fontWeight: FontWeight.w600)
                : null,
            error: errorText == null ? null : _ErrorLine(errorText!),
            suffixIcon: _fieldEnd(),
          ),
        ),
      ],
    ));
  }

  Widget? _fieldEnd() {
    final words = loadingLabel ?? unit;
    if (words == null) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 14, left: NvSpace.s2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (loadingLabel != null) ...[
          const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: NvColors.slate)),
          const SizedBox(width: 6),
        ],
        Text(words, style: NvText.body.copyWith(color: NvColors.slate)),
      ]),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = NvText.caption
        .copyWith(color: NvColors.problem, fontWeight: FontWeight.w600);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(top: 1),
        child: ExcludeSemantics(
            child:
                Icon(Icons.error_outline, size: 16, color: NvColors.problem)),
      ),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: style)),
    ]);
  }
}
