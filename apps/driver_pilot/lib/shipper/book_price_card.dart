// Book's price card: the price and where the payment goes.
import "package:flutter/material.dart";

import "../ui/format.dart";
import "../ui/tokens.dart";

/// The price and what happens to the payment. With the lane above and the full-price and cancel
/// lines beside the button, it holds what the shipper needs before money moves (sh-book-price).
class BookPriceCard extends StatelessWidget {
  const BookPriceCard(
      {required this.pricePaise, required this.carrier, super.key});
  final num pricePaise;

  /// The carrier's name, or "The carrier", at the start of a sentence.
  final String carrier;

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
            Text(
                "$carrier accepts after you pay. NaviG8r holds your payment and releases it after delivery.",
                style: NvText.body),
          ],
        ),
      );
}
