// Book's trip summary: route, carrier, dates and the capacity remaining as the weight is typed.
import "package:flutter/material.dart";

import "../ui/format.dart";
import "../ui/tokens.dart";
import "shipper_words.dart";

/// The lane being booked: route, carrier, dates and the capacity remaining once the weight typed so
/// far is taken off. An empty or unreadable weight takes nothing off; it never shows below 0.
class BookLaneSummary extends StatelessWidget {
  const BookLaneSummary({required this.lane, required this.typedWeightKg, super.key});
  final Map<String, dynamic> lane;
  final int? typedWeightKg;

  @override
  Widget build(BuildContext context) {
    final room = roomLeftKg(lane);
    final typed = typedWeightKg;
    final remaining = room == null || typed == null || typed <= 0
        ? room
        : (room - typed < 0 ? 0 : room - typed);
    final tooHeavyByKg =
        room != null && typed != null && typed > room ? typed - room : null;
    final dates = laneDates(lane);
    final carrier = lane["carrierDisplayName"]?.toString() ?? "Carrier";
    return Container(
      padding: const EdgeInsets.all(NvSpace.s4),
      decoration: BoxDecoration(
          color: NvColors.card,
          borderRadius: BorderRadius.circular(NvRadius.card),
          border: Border.all(color: NvColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(laneRoute(lane),
              style: NvText.bodyStrong.copyWith(color: NvColors.navyInk)),
          const SizedBox(height: NvSpace.s1),
          Wrap(spacing: NvSpace.s1, children: [
            Text(dates == null ? carrier : "$carrier · Leaves $dates",
                style: NvText.caption),
            if (remaining != null)
              Text(
                  tooHeavyByKg != null
                      ? "${formatKg(tooHeavyByKg)} more than the capacity remaining"
                      // A weight that fits exactly leaves 0 kg, a number like the rest, not "None".
                      : "Capacity remaining: ${formatKg(remaining)}",
                  style: NvText.caption.copyWith(
                      fontWeight: FontWeight.w700, color: NvColors.ink)),
          ]),
        ],
      ),
    );
  }
}
