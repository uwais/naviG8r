// Book's check of its two pins before paying (owner, 21 Oct 2026): the pin decides the place and the
// price, and the typed words are what the driver reads, so the shipper checks both by eye.
import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "../address_town.dart";
import "../location_editor.dart";
import "../ui/tokens.dart";

/// A place on Book as the check shows it: the words typed, its pin, Google's address for the pin, and
/// whether a dragged pin is still being named.
typedef BookPlace = ({String words, LatLng pin, PinAddress? pinAddress, bool naming});

/// Each pin's typed words and its Pin line, below the place boxes. The pins themselves are on the screen's
/// one map, under the boxes (owner, 5 Nov 2026: one map per screen).
class BookPinsCheck extends StatelessWidget {
  const BookPinsCheck({required this.pickup, required this.drop, super.key});
  final BookPlace pickup;
  final BookPlace drop;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(NvSpace.s4),
        decoration: BoxDecoration(
            color: NvColors.card,
            borderRadius: BorderRadius.circular(NvRadius.card),
            border: Border.all(color: NvColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Check the pins before you pay", style: NvText.heading),
            for (final (title, place) in [("Pickup", pickup), ("Drop", drop)]) ...[
              const SizedBox(height: NvSpace.s3),
              Text("$title: ${place.words}", style: NvText.bodyStrong),
              Text(
                  place.naming
                      ? "Waiting for the address at the pin."
                      : pinAddressLine(place.pinAddress),
                  style: NvText.caption),
            ],
          ],
        ),
      );
}

/// One short line per pin directly above Book and pay (owner, 21 Oct 2026: "Pin lines just above Book
/// and pay"). Each is cut to one line on screen, so the town comes first and a long address cannot hide it;
/// a screen reader hears it whole.
class BookPinLines extends StatelessWidget {
  const BookPinLines({required this.pickup, required this.drop, super.key});
  final BookPlace pickup;
  final BookPlace drop;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (title, place) in [("Pickup", pickup), ("Drop", drop)])
            _oneLine(_pinLine(title, place)),
        ],
      );

  /// While a dragged pin is named, and when there is no address, the same words as the pins check.
  static String _pinLine(String title, BookPlace place) {
    final address = place.pinAddress?.address;
    if (place.naming) return "$title pin: Waiting for the address at the pin.";
    if (address == null) {
      return "$title ${pinAddressLine(place.pinAddress).replaceFirst("Pin: ", "pin: ")}";
    }
    final town = townOfAddress(address);
    return town == address ? "$title pin: $address" : "$title pin in $town: $address";
  }

  static Widget _oneLine(String words) => Semantics(
        label: words,
        excludeSemantics: true,
        child: Text(words,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: NvText.caption),
      );
}
