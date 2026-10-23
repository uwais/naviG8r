import "dart:async";

import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:flutter/services.dart";

import "tokens.dart";

enum NvCopyRowState {
  ready,
  loading,

  /// There is no value and there will not be one, for example a carrier with no transporter ID.
  empty,

  /// The value exists only later, for example the truck before the carrier accepts.
  notYet,
}

/// A value the person copies into the government portal: what it is, the value in the mono
/// face, and the portal's own name for the field. The value is copied without spaces even
/// when it is shown in groups.
class NvCopyRow extends StatefulWidget {
  const NvCopyRow(
      {required this.label,
      this.value,
      this.portalField,
      this.noValueWords,
      this.guidance,
      this.state = NvCopyRowState.ready,
      super.key});

  /// "Truck number". Also names the copy in the button label and the announcement.
  final String label;
  final String? value;

  /// "Portal field: Vehicle No. (Part B)", shown under a ready value.
  final String? portalField;

  /// Shown where the value would be when the row is empty or not yet available.
  final String? noValueWords;

  /// The caption under a loading, empty or not-yet row.
  final String? guidance;
  final NvCopyRowState state;

  @override
  State<NvCopyRow> createState() => _NvCopyRowState();
}

class _NvCopyRowState extends State<NvCopyRow> {
  static const _copiedFor = Duration(seconds: 3);
  static const _copyFailedWords =
      "Could not copy. Press and hold the number to copy it.";

  bool _copied = false;
  bool _copyFailed = false;
  Timer? _copiedTimer;

  String get _labelInSentence =>
      widget.label[0].toLowerCase() + widget.label.substring(1);

  bool get _canCopy =>
      widget.state == NvCopyRowState.ready && (widget.value ?? "").isNotEmpty;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final direction = Directionality.of(context);
    try {
      await Clipboard.setData(
          ClipboardData(text: widget.value!.replaceAll(" ", "")));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _copied = false;
        _copyFailed = true;
      });
      SemanticsService.announce(_copyFailedWords, direction,
          assertiveness: Assertiveness.assertive);
      return;
    }
    if (!mounted) return;
    setState(() {
      _copied = true;
      _copyFailed = false;
    });
    SemanticsService.announce("${widget.label} copied.", direction);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(_copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final lines = <Widget>[
      Text(widget.label,
          style: NvText.bodyStrong.copyWith(
              fontSize: 13, height: 18 / 13, color: NvColors.navyInk)),
      const SizedBox(height: NvSpace.s1),
      switch (state) {
        NvCopyRowState.ready =>
          SelectableText(widget.value ?? "", style: NvText.id),
        NvCopyRowState.loading => ExcludeSemantics(
            child: Container(
                height: 22,
                width: 148,
                decoration: BoxDecoration(
                    color: NvColors.line,
                    borderRadius: BorderRadius.circular(NvRadius.sm)))),
        NvCopyRowState.empty ||
        NvCopyRowState.notYet =>
          Text(widget.noValueWords ?? "", style: NvText.body),
      },
      const SizedBox(height: NvSpace.s1),
      if (_copyFailed)
        Semantics(
          liveRegion: true,
          child: Text(_copyFailedWords,
              style: NvText.caption.copyWith(
                  color: NvColors.problem, fontWeight: FontWeight.w600)),
        )
      else if (state == NvCopyRowState.ready && widget.portalField != null)
        Text(widget.portalField!, style: NvText.caption)
      else if (state != NvCopyRowState.ready && widget.guidance != null)
        Text(widget.guidance!, style: NvText.caption),
    ];
    return Container(
      padding: const EdgeInsets.all(NvSpace.s3),
      decoration: BoxDecoration(
          color: NvColors.sunken,
          borderRadius: BorderRadius.circular(NvRadius.button)),
      child: Row(
        children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: lines)),
          if (state != NvCopyRowState.empty) ...[
            const SizedBox(width: NvSpace.s3),
            _copyButton(),
          ],
        ],
      ),
    );
  }

  Widget _copyButton() {
    if (_copied) {
      return OutlinedButton.icon(
        onPressed: _copy,
        style: OutlinedButton.styleFrom(
            foregroundColor: NvColors.good,
            side: const BorderSide(color: NvColors.good)),
        icon: const Icon(Icons.check, size: 18),
        label: Semantics(
            label: "${widget.label} copied",
            excludeSemantics: true,
            child: const Text("Copied")),
      );
    }
    return OutlinedButton(
      onPressed: _canCopy ? _copy : null,
      style: OutlinedButton.styleFrom(
          side: _canCopy
              ? const BorderSide(color: NvColors.controlBorder)
              : BorderSide.none,
          backgroundColor: _canCopy ? NvColors.card : Colors.transparent),
      // Screen readers hear what is copied: "Copy truck number KA01AB1234".
      child: Semantics(
          label: _canCopy ? "Copy $_labelInSentence ${widget.value}" : null,
          excludeSemantics: _canCopy,
          child: const Text("Copy")),
    );
  }
}
