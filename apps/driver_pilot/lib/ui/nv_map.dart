import "package:flutter/material.dart";

import "nv_button.dart";
import "tokens.dart";

enum NvMapState { ready, loading, locationOff, failed }

/// The one small map on a screen, around a map the app already draws (for example
/// routePreviewMap). It only shows places: the screen's text fields come first and keep
/// working whatever state the map is in.
class NvMap extends StatelessWidget {
  const NvMap(
      {required this.map,
      this.state = NvMapState.ready,
      this.pinsLabel = "Pickup and drop",
      this.pinTitles,
      this.failedHelp,
      this.onTurnOnLocation,
      super.key});

  /// The Google map itself. It is drawn at this widget's height whatever height it asks for.
  final Widget map;
  final NvMapState state;

  /// Names the pins in words, so they are not told apart by colour alone. Unused when [pinTitles] is set.
  final String pinsLabel;

  /// For a map drawn with place_pin_icons.dart's dots: the chip becomes a legend, each dot beside its
  /// title ("Pickup", "Drop"), so the words say which dot is which.
  final ({String start, String end})? pinTitles;

  /// The line under "The map could not load", saying what still works without it.
  final String? failedHelp;

  /// Null hides the "Turn on location" button.
  final VoidCallback? onTurnOnLocation;

  static const height = 140.0;

  @override
  Widget build(BuildContext context) => switch (state) {
        NvMapState.ready => SizedBox(
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NvRadius.card),
              child: Stack(children: [
                Positioned.fill(child: map),
                // Left and right both set, so a legend too wide for the map wraps instead of overflowing.
                Positioned(
                  left: NvSpace.s2,
                  right: NvSpace.s2,
                  bottom: NvSpace.s2,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: NvSpace.s2, vertical: NvSpace.s1),
                      decoration: BoxDecoration(
                          color: NvColors.card,
                          borderRadius: BorderRadius.circular(NvRadius.sm),
                          border: Border.all(color: NvColors.line)),
                      child: switch (pinTitles) {
                        null => Text(pinsLabel, style: _chipText),
                        final titles => _PinLegend(titles),
                      },
                    ),
                  ),
                ),
              ]),
            ),
          ),
        NvMapState.loading => _MapPanel(
            holdsMapHeight: true,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (!MediaQuery.disableAnimationsOf(context)) ...[
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: NvColors.slate)),
                  const SizedBox(width: NvSpace.s2),
                ],
                const Flexible(
                    child: Text("Loading the map", style: NvText.caption)),
              ]),
            ],
          ),
        NvMapState.locationOff => _MapPanel(children: [
            Text("Location is off",
                style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
            const SizedBox(height: NvSpace.s1),
            Text(
                "Type the pickup place above, or turn on location to use where you are.",
                style: NvText.caption.copyWith(color: NvColors.ink)),
            if (onTurnOnLocation != null) ...[
              const SizedBox(height: NvSpace.s3),
              NvButton(
                  label: "Turn on location",
                  onPressed: onTurnOnLocation,
                  kind: NvButtonKind.secondary),
            ],
          ]),
        NvMapState.failed => _MapPanel(children: [
            Semantics(
              liveRegion: true,
              child: Text("The map could not load",
                  style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
            ),
            if (failedHelp != null) ...[
              const SizedBox(height: NvSpace.s1),
              Text(failedHelp!,
                  style: NvText.caption.copyWith(color: NvColors.ink)),
            ],
          ]),
      };
}

final _chipText =
    NvText.caption.copyWith(fontWeight: FontWeight.w600, color: NvColors.navyInk);

/// The pins' dots as place_pin_icons.dart draws them, each beside its title. A screen reader hears the
/// same thing in words: "Pickup is the navy dot. Drop is the gold dot."
class _PinLegend extends StatelessWidget {
  const _PinLegend(this.titles);
  final ({String start, String end}) titles;

  static const _dotSize = 10.0;

  Widget _entry(String title, Color fill, {required bool ringed}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: ringed ? Border.all(color: NvColors.navy, width: 2) : null),
        ),
        const SizedBox(width: NvSpace.s1),
        Flexible(child: Text(title, style: _chipText)),
      ]);

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        excludeSemantics: true,
        label: "${titles.start} is the navy dot. ${titles.end} is the gold dot.",
        child: Wrap(
          spacing: NvSpace.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _entry(titles.start, NvColors.navy, ringed: false),
            _entry(titles.end, NvColors.gold, ringed: true),
          ],
        ),
      );
}

/// The grey box that stands in for the map. It grows with large text instead of clipping.
class _MapPanel extends StatelessWidget {
  const _MapPanel({required this.children, this.holdsMapHeight = false});
  final List<Widget> children;

  /// While loading, the panel keeps the map's height and centres its words, so the screen does not jump.
  final bool holdsMapHeight;

  @override
  Widget build(BuildContext context) => Container(
        constraints:
            BoxConstraints(minHeight: holdsMapHeight ? NvMap.height : 0),
        padding: const EdgeInsets.all(NvSpace.s4),
        alignment: holdsMapHeight ? Alignment.center : Alignment.topLeft,
        decoration: BoxDecoration(
            color: NvColors.sunken,
            borderRadius: BorderRadius.circular(NvRadius.card)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}
