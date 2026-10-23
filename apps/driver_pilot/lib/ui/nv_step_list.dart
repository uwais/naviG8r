import "package:flutter/material.dart";

import "tokens.dart";

enum NvStepState { done, yours, waiting, later, problem }

/// One row of an [NvStepList]: the step's name, who does it, and for the person's own step
/// (or a waiting one) a panel the screen fills with its sentence and button.
class NvStep {
  const NvStep(
      {required this.title,
      required this.state,
      this.who,
      this.panel,
      this.panelAlwaysShown = false});
  final String title;
  final NvStepState state;

  /// The line under the title: who acts ("You", the carrier's name), or for a done step what happened.
  final String? who;

  /// Shown only for yours, problem and waiting steps, unless [panelAlwaysShown]. A waiting panel
  /// must hold no button.
  final Widget? panel;

  /// Also shows the panel on a done step (white, as the saved e-way bill in sh-ewb-checking) or
  /// a later one (grey, as in sh-ewb-ask).
  final bool panelAlwaysShown;
}

/// The ordered steps of a shipment or booking. Step states differ by marker as well as colour:
/// tick (done), number with a halo (yours), clock (waiting), number (later), "!" (problem).
class NvStepList extends StatelessWidget {
  const NvStepList(
      {required this.steps,
      required this.listName,
      this.loading = false,
      this.loadingWords,
      super.key});
  final List<NvStep> steps;

  /// What a screen reader calls the list, for example "Steps for this shipment".
  final String listName;
  final bool loading;

  /// Shown under the placeholder rows while loading, for example "Loading this shipment's steps."
  final String? loadingWords;

  @override
  Widget build(BuildContext context) {
    if (loading) return _LoadingSteps(words: loadingWords);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: listName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < steps.length; index++)
            _StepRow(
                step: steps[index],
                number: index + 1,
                count: steps.length,
                isLast: index == steps.length - 1),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow(
      {required this.step,
      required this.number,
      required this.count,
      required this.isLast});
  final NvStep step;
  final int number;
  final int count;
  final bool isLast;

  String get _spokenLabel {
    final whoPart = step.who == null ? "" : ", ${step.who}";
    return switch (step.state) {
      NvStepState.done => "Done: ${step.title}",
      NvStepState.yours ||
      NvStepState.problem =>
        "Your step: ${step.title}$whoPart",
      NvStepState.waiting => "In progress: ${step.title}$whoPart",
      NvStepState.later =>
        "Step $number of $count, not yet: ${step.title}$whoPart",
    };
  }

  bool get _showsPanel =>
      step.panel != null &&
      (step.panelAlwaysShown ||
          step.state == NvStepState.yours ||
          step.state == NvStepState.problem ||
          step.state == NvStepState.waiting);

  @override
  Widget build(BuildContext context) {
    final isLater = step.state == NvStepState.later;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(children: [
              _StepMarker(state: step.state, number: number),
              if (!isLast)
                Expanded(
                  child: Center(
                    child: Container(
                        width: 2,
                        color: step.state == NvStepState.done
                            ? NvColors.navy
                            : NvColors.line),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: NvSpace.s3),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : NvSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: _spokenLabel,
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.only(top: NvSpace.s1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title,
                              style: NvText.bodyStrong.copyWith(
                                  color: isLater
                                      ? NvColors.slate
                                      : NvColors.navyInk)),
                          if (step.who != null)
                            Text(step.who!, style: NvText.caption),
                        ],
                      ),
                    ),
                  ),
                  if (_showsPanel) ...[
                    const SizedBox(height: NvSpace.s3),
                    _StepPanel(state: step.state, child: step.panel!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({required this.state, required this.number});
  final NvStepState state;
  final int number;

  @override
  Widget build(BuildContext context) {
    final numberText = MediaQuery.withNoTextScaling(
        child: Text("$number",
            style: NvText.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: state == NvStepState.later
                    ? NvColors.slate
                    : NvColors.navyInk)));
    final (fill, border, Widget mark) = switch (state) {
      NvStepState.done => (
          NvColors.navy,
          NvColors.navy,
          const Icon(Icons.check, size: 18, color: NvColors.onNavy)
        ),
      NvStepState.yours => (NvColors.card, NvColors.navy, numberText),
      NvStepState.waiting => (
          NvColors.card,
          NvColors.navy,
          const Icon(Icons.schedule, size: 18, color: NvColors.navy)
        ),
      NvStepState.later => (NvColors.card, NvColors.controlBorder, numberText),
      NvStepState.problem => (
          NvColors.problemTint,
          NvColors.problem,
          MediaQuery.withNoTextScaling(
              child: Text("!",
                  style: NvText.bodyStrong.copyWith(color: NvColors.problem)))
        ),
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 2),
        // The halo marks the person's own step without relying on colour.
        boxShadow: state == NvStepState.yours
            ? const [BoxShadow(color: NvColors.line, spreadRadius: 4)]
            : null,
      ),
      child: mark,
    );
  }
}

class _StepPanel extends StatelessWidget {
  const _StepPanel({required this.state, required this.child});
  final NvStepState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final decoration = switch (state) {
      NvStepState.waiting || NvStepState.later => BoxDecoration(
          color: NvColors.sunken,
          borderRadius: BorderRadius.circular(NvRadius.button)),
      NvStepState.done => BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.line)),
      NvStepState.problem => BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.problem)),
      _ => BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.navy)),
    };
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: decoration,
      child: child,
    );
  }
}

class _LoadingSteps extends StatelessWidget {
  const _LoadingSteps({required this.words});
  final String? words;

  @override
  Widget build(BuildContext context) {
    Widget placeholderRow(double barWidth) => ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(bottom: NvSpace.s3),
            child: Row(children: [
              Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                      color: NvColors.sunken, shape: BoxShape.circle)),
              const SizedBox(width: NvSpace.s3),
              Container(
                  width: barWidth,
                  height: 14,
                  decoration: BoxDecoration(
                      color: NvColors.sunken,
                      borderRadius: BorderRadius.circular(NvRadius.sm))),
            ]),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        placeholderRow(196),
        placeholderRow(148),
        if (words != null) Text(words!, style: NvText.caption),
      ],
    );
  }
}
