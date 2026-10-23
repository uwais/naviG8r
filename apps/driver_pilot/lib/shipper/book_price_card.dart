// Book's price card: the price and what happens after Book and pay, with the two notes a desktop shows
// under the fields instead.
import "package:flutter/material.dart";

import "../ui/format.dart";
import "../ui/tokens.dart";

const priceChangesNote =
    "If you change the weight or move a pin, the price may change.";

const paymentPartnerNote =
    "Book and pay opens our payment partner's screen. There you choose how to pay.";

/// The price and what happens after Book and pay. With the lane above and the words beside the
/// button, it holds everything the confirm sheet used to show before money moved (sh-book-price).
class BookPriceCard extends StatelessWidget {
  const BookPriceCard(
      {required this.pricePaise, required this.carrier, required this.withNotes, super.key});
  final num pricePaise;
  final String carrier;
  final bool withNotes;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.card,
            borderRadius: BorderRadius.circular(NvRadius.card),
            border: Border.all(color: NvColors.navy, width: 1.5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: NvSpace.s3,
              children: [
                const Text("Price", style: NvText.heading),
                Text(formatRupees(pricePaise), style: NvText.title),
              ],
            ),
            const SizedBox(height: NvSpace.s2),
            Text("After you pay, $carrier is asked to accept and name the truck.",
                style: NvText.body),
            const SizedBox(height: NvSpace.s2),
            const Text("NaviG8r holds your payment and releases it after delivery.",
                style: NvText.body),
            if (withNotes) ...[
              const SizedBox(height: NvSpace.s2),
              const Text(paymentPartnerNote, style: NvText.body),
              const SizedBox(height: NvSpace.s2),
              const Text(priceChangesNote, style: NvText.caption),
            ],
          ],
        ),
      );
}
