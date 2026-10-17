import "package:flutter/material.dart";
import "package:flutter/semantics.dart";

import "nv_button.dart";
import "tokens.dart";

/// Opens [builder]'s sheet over the screen. Focus moves into the sheet and returns to
/// the opener when it closes. With reduce-motion on, the sheet appears without sliding.
Future<T?> showNvSheet<T>(
    {required BuildContext context, required WidgetBuilder builder}) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    sheetAnimationStyle: reduceMotion
        ? AnimationStyle(
            duration: Duration.zero, reverseDuration: Duration.zero)
        : null,
    builder: builder,
  );
}

/// Closes the sheet after its action worked and tells a screen reader what happened, for
/// example "Accepted with KA01AB1234. Sharma Textiles can make the e-way bill now."
void closeNvSheetAfterSuccess<T>(BuildContext context,
    {required String announcement, T? result}) {
  final direction = Directionality.of(context);
  Navigator.of(context).pop<T>(result);
  SemanticsService.announce(announcement, direction);
}

/// One decision on top of a screen: a question as the title, the choices, then the primary
/// action and a neutral way out of equal size. The sheet holds no state; the screen passes
/// what is chosen, loading and any error, so an error keeps the sheet open and the choice kept.
class NvSheet extends StatelessWidget {
  const NvSheet(
      {required this.title,
      required this.primaryLabel,
      required this.onPrimary,
      this.message,
      this.errorText,
      this.choices = const [],
      this.disabledReason,
      this.loading = false,
      this.loadingLabel,
      this.cancelLabel = "Cancel",
      this.onCancel,
      super.key});

  /// A question, for example "Which truck carries this trip?"
  final String title;
  final String? message;

  /// Why the last try failed. The sheet stays open while this shows.
  final String? errorText;
  final List<Widget> choices;
  final String primaryLabel;

  /// Null disables the primary action; [disabledReason] then says why, under it.
  final VoidCallback? onPrimary;
  final String? disabledReason;
  final bool loading;

  /// The primary's words while loading, for example "Accepting".
  final String? loadingLabel;
  final String cancelLabel;

  /// Defaults to closing the sheet.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    const fullWidth = Size.fromHeight(NvSpace.targetMin);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            namesRoute: true,
            child: Text(title,
                style: NvText.heading.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (message != null) ...[
            const SizedBox(height: NvSpace.s2),
            Text(message!, style: NvText.caption.copyWith(color: NvColors.ink)),
          ],
          if (errorText != null) ...[
            const SizedBox(height: NvSpace.s3),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(NvSpace.s3),
                decoration: BoxDecoration(
                    color: NvColors.problemTint,
                    borderRadius: BorderRadius.circular(NvRadius.button)),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ExcludeSemantics(
                          child: Icon(Icons.error_outline,
                              size: 20, color: NvColors.problem)),
                      const SizedBox(width: NvSpace.s2),
                      Expanded(child: Text(errorText!, style: NvText.body)),
                    ]),
              ),
            ),
          ],
          for (final choice in choices) ...[
            const SizedBox(height: NvSpace.s2),
            AbsorbPointer(absorbing: loading, child: choice),
          ],
          const SizedBox(height: NvSpace.s4),
          NvButton(
            label: primaryLabel,
            onPressed: onPrimary,
            disabledReason: disabledReason,
            loading: loading,
            loadingLabel: loadingLabel,
            fullWidth: true,
          ),
          const SizedBox(height: NvSpace.s3),
          // Not an NvButton: Cancel is held while the action runs, and NvButton requires a
          // reason line for every disabled state, which copy.md does not give for this one.
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: fullWidth),
            onPressed: loading
                ? null
                : (onCancel ?? () => Navigator.of(context).maybePop()),
            child: Text(cancelLabel, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
