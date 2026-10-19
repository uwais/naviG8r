import "package:flutter/material.dart";

import "tokens.dart";

/// Primary is the one main action in a screen region; quiet is for low-risk side paths.
enum NvButtonKind { primary, secondary, destructive, quiet }

/// The app's button. The label says the outcome. A disabled button always shows its reason
/// under it, and buttons never turn red on an error: the error goes next to what failed.
class NvButton extends StatelessWidget {
  const NvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = NvButtonKind.primary,
    this.disabledReason,
    this.loading = false,
    this.loadingLabel,
    this.successLabel,
    this.semanticsLabel,
    this.forDriver = false,
    this.fullWidth = false,
  }) : assert(
            onPressed != null ||
                loading ||
                successLabel != null ||
                disabledReason != null,
            "a disabled button always says why");

  final String label;

  /// Null disables the button; [disabledReason] then says why, in words under it.
  final VoidCallback? onPressed;
  final NvButtonKind kind;
  final String? disabledReason;

  /// While loading the button keeps its colours, adds a progress ring and cannot be pressed.
  final bool loading;

  /// The words while loading, such as "Getting price" for "Get price". Defaults to [label].
  final String? loadingLabel;

  /// Shown with a tick instead of [label], such as "Saved" or "Copied".
  final String? successLabel;

  /// What a screen reader hears instead of [label] when the label alone does not say what the
  /// button acts on, such as "Copy all transport details" for "Copy all".
  final String? semanticsLabel;

  /// Driver primaries are 56 dp tall, for one-handed use in a cab.
  final bool forDriver;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final showsSuccess = successLabel != null && !loading;
    final disabled = onPressed == null && !loading && !showsSuccess;
    final words = loading
        ? (loadingLabel ?? label)
        : (showsSuccess ? successLabel! : label);
    final colours = disabled
        ? _disabledColours
        : showsSuccess
            ? _successColours(kind)
            : _colours(kind);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Widget? marker;
    if (loading && !reduceMotion) {
      marker = SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: colours.foreground),
      );
    } else if (showsSuccess) {
      marker = const Icon(Icons.check, size: 18);
    }
    final spokenWords = words == label ? semanticsLabel : null;
    final content = marker == null
        ? Text(words, textAlign: TextAlign.center, semanticsLabel: spokenWords)
        : Row(mainAxisSize: MainAxisSize.min, children: [
            ExcludeSemantics(child: marker),
            const SizedBox(width: NvSpace.s2),
            Flexible(
                child: Text(words,
                    textAlign: TextAlign.center, semanticsLabel: spokenWords)),
          ]);

    final height = forDriver ? NvSpace.targetDriver : NvSpace.targetMin;
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(
          Size(fullWidth ? double.infinity : NvSpace.targetMin, height)),
      backgroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.pressed)
              ? colours.pressedBackground
              : colours.background),
      foregroundColor: WidgetStatePropertyAll(colours.foreground),
      // The pressed colour above is the whole pressed look; the default overlay would wash it out.
      overlayColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.pressed) ? Colors.transparent : null),
      side: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.focused) ? focusRing : colours.border),
    );
    final tap = (loading || showsSuccess) ? null : onPressed;
    final button = switch (kind) {
      NvButtonKind.primary =>
        FilledButton(onPressed: tap, style: style, child: content),
      NvButtonKind.quiet =>
        TextButton(onPressed: tap, style: style, child: content),
      NvButtonKind.secondary ||
      NvButtonKind.destructive =>
        OutlinedButton(onPressed: tap, style: style, child: content),
    };
    if (!disabled || disabledReason == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        button,
        const SizedBox(height: NvSpace.s1),
        Text(disabledReason!, style: NvText.caption),
      ],
    );
  }

  /// A 2 dp navy ring with a 2 dp gap outside the button. A stroke alignment of 3 places the
  /// stroke between 2 and 4 dp outside the edge (BorderSide.strokeAlign has no upper bound).
  static const focusRing =
      BorderSide(color: NvColors.focus, width: 2, strokeAlign: 3);
}

class _ButtonColours {
  const _ButtonColours(
      {required this.background,
      required this.pressedBackground,
      required this.foreground,
      this.border = BorderSide.none});

  final Color background;
  final Color pressedBackground;
  final Color foreground;
  final BorderSide border;
}

const _disabledColours = _ButtonColours(
    background: NvColors.sunken,
    pressedBackground: NvColors.sunken,
    foreground: NvColors.slate);

_ButtonColours _colours(NvButtonKind kind) => switch (kind) {
      NvButtonKind.primary => const _ButtonColours(
          background: NvColors.navy,
          pressedBackground: NvColors.navyDeep,
          foreground: NvColors.onNavy),
      NvButtonKind.secondary => const _ButtonColours(
          background: NvColors.card,
          pressedBackground: NvColors.sunken,
          foreground: NvColors.navy,
          border: BorderSide(color: NvColors.controlBorder)),
      NvButtonKind.destructive => const _ButtonColours(
          background: NvColors.card,
          pressedBackground: NvColors.problemTint,
          foreground: NvColors.problem,
          border: BorderSide(color: NvColors.problem)),
      NvButtonKind.quiet => const _ButtonColours(
          background: Colors.transparent,
          pressedBackground: NvColors.sunken,
          foreground: NvColors.navy),
    };

_ButtonColours _successColours(NvButtonKind kind) =>
    kind == NvButtonKind.primary
        ? const _ButtonColours(
            background: NvColors.good,
            pressedBackground: NvColors.good,
            foreground: NvColors.card)
        : const _ButtonColours(
            background: NvColors.card,
            pressedBackground: NvColors.card,
            foreground: NvColors.good,
            border: BorderSide(color: NvColors.good));
