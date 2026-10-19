import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "../google_geocoding.dart";

/// A pickup or drop: the words the shipper typed and the map point the price and the match use.
/// A point counts only for the words it was found for, or the words beside it when the shipper
/// dragged its pin; typing other words looks those up.
class PlaceInput {
  PlaceInput({String words = "", this.point})
      : words = TextEditingController(text: words),
        _pointFor = point == null ? null : words.trim();

  final TextEditingController words;
  LatLng? point;
  String? _pointFor;
  String? error;

  String get text => words.text.trim();
  bool get placed => point != null && _pointFor == text;

  void foundAt(LatLng found) {
    point = found;
    _pointFor = text;
  }

  void pinnedAt(LatLng pin) => foundAt(pin);

  /// Looks up the words when they have no point yet. Sets [error] and returns false when the
  /// place cannot be used.
  Future<bool> place(PlaceFinder findPlace, {required String emptyError}) async {
    error = null;
    if (text.isEmpty) {
      error = emptyError;
      return false;
    }
    if (placed) return true;
    final outcome = await findPlace(text);
    if (!outcome.isOk) {
      // Match has no map, and Book pins only a place found earlier, so no pin is promised.
      error = placeSearchFailureSentence(outcome.failure, pinOnMap: false);
      return false;
    }
    foundAt(outcome.position!);
    return true;
  }

  void dispose() => words.dispose();
}
