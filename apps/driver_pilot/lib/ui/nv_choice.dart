import "package:flutter/material.dart";

import "tokens.dart";

/// One option in NvChoiceChips or NvChoiceRows.
class NvChoice<T> {
  const NvChoice(this.value, this.label,
      {this.caption, this.labelIsIdentifier = false});

  final T value;
  final String label;

  /// A second line under the label (rows only), such as "Medium truck".
  final String? caption;

  /// Truck numbers and other IDs are set in the mono face.
  final bool labelIsIdentifier;
}

/// Short fixed options as chips, such as Small, Medium, Large. Nothing is chosen until the
/// person chooses: [selected] starts null.
class NvChoiceChips<T> extends StatelessWidget {
  const NvChoiceChips({
    super.key,
    this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.disabledReason,
    this.trailing,
  }) : assert(onChanged != null || disabledReason != null,
            "a disabled choice always says why");

  final String? label;
  final List<NvChoice<T>> options;
  final T? selected;

  /// Null disables every chip; [disabledReason] then says why.
  final ValueChanged<T>? onChanged;
  final String? disabledReason;

  /// Sits after the last chip in the same flow, such as a Refresh button, so it takes a line of
  /// its own only when the chips leave no room beside the last one.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return _Labelled(
      label: label,
      reason: disabled ? disabledReason : null,
      child: Wrap(
        spacing: NvSpace.s2,
        runSpacing: NvSpace.s2,
        children: [
          for (final option in options)
            _chip(option, option.value == selected, disabled),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }

  Widget _chip(NvChoice<T> option, bool chosen, bool disabled) {
    return ChoiceChip(
      label: Text(option.label),
      selected: chosen,
      onSelected: disabled ? null : (_) => onChanged!(option.value),
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.symmetric(
          horizontal: NvSpace.s2, vertical: NvSpace.s2),
      labelStyle: NvText.bodyStrong.copyWith(
          color: chosen
              ? NvColors.onNavy
              : (disabled ? NvColors.slate : NvColors.navy)),
      backgroundColor: NvColors.card,
      selectedColor: NvColors.navy,
      disabledColor: NvColors.sunken,
      side: BorderSide(
          color: chosen
              ? NvColors.navy
              : (disabled ? Colors.transparent : NvColors.controlBorder)),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NvRadius.pill)),
    );
  }
}

/// Options as full-width radio rows, such as trucks or companies. Nothing is chosen until the
/// person chooses: [selected] starts null.
class NvChoiceRows<T> extends StatelessWidget {
  const NvChoiceRows({
    super.key,
    this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.disabledReason,
  }) : assert(onChanged != null || disabledReason != null,
            "a disabled choice always says why");

  final String? label;
  final List<NvChoice<T>> options;
  final T? selected;

  /// Null disables every row; [disabledReason] then says why.
  final ValueChanged<T>? onChanged;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return _Labelled(
      label: label,
      reason: disabled ? disabledReason : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, option) in options.indexed) ...[
            if (index > 0) const SizedBox(height: NvSpace.s2),
            _row(option, option.value == selected, disabled),
          ],
        ],
      ),
    );
  }

  Widget _row(NvChoice<T> option, bool chosen, bool disabled) {
    final BorderSide border;
    if (chosen) {
      border = const BorderSide(color: NvColors.navy, width: 2);
    } else if (disabled) {
      border = BorderSide.none;
    } else {
      border = const BorderSide(color: NvColors.controlBorder);
    }
    final labelStyle = option.labelIsIdentifier
        ? NvText.id.copyWith(fontWeight: FontWeight.w600)
        : NvText.bodyStrong;
    return RadioListTile<T>(
      value: option.value,
      groupValue: selected,
      onChanged: disabled
          ? null
          : (value) {
              if (value != null) onChanged!(value);
            },
      title: Text(option.label,
          style: disabled
              ? labelStyle.copyWith(color: NvColors.slate)
              : labelStyle),
      subtitle: option.caption == null
          ? null
          : Text(option.caption!, style: NvText.caption),
      activeColor: NvColors.navy,
      tileColor: disabled ? NvColors.sunken : NvColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: NvSpace.s1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NvRadius.input),
        side: border,
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled(
      {required this.label, required this.reason, required this.child});

  final String? label;
  final String? reason;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: NvText.bodyStrong),
          const SizedBox(height: 6),
        ],
        child,
        if (reason != null) ...[
          const SizedBox(height: NvSpace.s1),
          Text(reason!, style: NvText.caption),
        ],
      ],
    );
  }
}
