import "package:flutter/material.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";

import "../google_geocoding.dart";

/// Turns typed place words into a map point. Screens take it as a parameter so tests can stand
/// in for the geocoding service.
typedef PlaceFinder = Future<GeocodeOutcome> Function(String place);

/// A pickup or drop: the words the shipper typed and the map point the price and the match use.
/// A point counts only for the words it was found for, unless the shipper dragged its pin.
class PlaceInput {
  PlaceInput({String words = "", this.point})
      : words = TextEditingController(text: words),
        _pointFor = point == null ? null : words.trim();

  final TextEditingController words;
  LatLng? point;
  String? _pointFor;
  bool _pinnedByHand = false;
  String? error;

  String get text => words.text.trim();
  bool get placed => point != null && (_pinnedByHand || _pointFor == text);

  void foundAt(LatLng found) {
    point = found;
    _pointFor = text;
  }

  void pinnedAt(LatLng pin) {
    point = pin;
    _pinnedByHand = true;
  }

  /// Looks up the words when they have no point yet. Sets [error] and returns false when the
  /// place cannot be used.
  Future<bool> place(PlaceFinder findPlace,
      {required String emptyError, required String notFoundError}) async {
    error = null;
    if (text.isEmpty) {
      error = emptyError;
      return false;
    }
    if (placed) return true;
    final outcome = await findPlace(text);
    if (!outcome.isOk) {
      error = notFoundError;
      return false;
    }
    foundAt(outcome.position!);
    return true;
  }

  void dispose() => words.dispose();
}
