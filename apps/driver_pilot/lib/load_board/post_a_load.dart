// Post a load (Load Board phase 1, 4 Nov 2026): a shipper whose route search found nothing posts the load, and
// carriers going that way can add a trip for it. It opens from the search, which fills in the places and weight.
// No price shows here: the price comes only in the booking, once a carrier has added a trip.
import "package:dio/dio.dart" show DioException;
import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../address_town.dart";
import "../plain_error_sentence.dart";
import "../shipper/announce.dart";
import "../shipper/book_a_lane.dart" show SearchedPlace;
import "../shipper/shipper_scaffold.dart";
import "../shipper/shipper_words.dart";
import "../pilot_api.dart";
import "../ui/format.dart";
import "../ui/nv_action_bar.dart";
import "../ui/nv_button.dart";
import "../ui/nv_choice.dart";
import "../ui/nv_field.dart";
import "../ui/nv_message.dart";
import "../ui/tokens.dart";
import "posted_load_words.dart";

/// The route search as it was when it found nothing, handed over as the router's extra, never in the link:
/// its places are street addresses.
class LoadToPost {
  const LoadToPost(
      {required this.pickup, required this.drop, required this.weightKg});
  final SearchedPlace pickup;
  final SearchedPlace drop;
  final int weightKg;
}

// The server's rules (features/loadBoard/postedLoad.ts).
const _daysAheadForFirstPickup = 7;
const _daysInPickupWindow = 3;
const _maxNoteLength = 300;
const _maxTownLength = 80;
const _maxPackageCount = 10000;
const _maxPackageSide = 10000;
const _maxTotalVolume = 100000;

enum _SizeKind { sizes, totalVolume }

/// The town to fill in for a searched place: from the pin's Google address, else from typed words with more
/// than one part. Empty otherwise, so the shipper types it: [townOfAddress] gives a one-part address back
/// whole, and that could be a street address carriers would then see.
String townToPost(SearchedPlace place) {
  for (final address in [place.pinAddress?.address, place.words]) {
    final parts = address?.split(",").where((part) => part.trim().isNotEmpty);
    if (parts != null && parts.length > 1) return townOfAddress(address!);
  }
  return "";
}

/// A refusal from the server in words, or null for one this form has no sentence for.
String? _refusalSentence(Object error) {
  final body = error is DioException ? error.response?.data : null;
  final code = body is Map ? body["error"] : null;
  return switch (code) {
    "too_many_open_loads" =>
      "Your company already has 10 open loads. Withdraw one under My loads to post another.",
    "earliest_pickup_in_the_past" =>
      "The first pickup day has passed. Choose today or later.",
    "earliest_pickup_too_far_ahead" =>
      "Choose a first pickup day within 7 days from today.",
    "latest_pickup_before_earliest" =>
      "The last pickup day must be on or after the first.",
    "pickup_window_too_long" =>
      "The last pickup day can be at most 3 days after the first.",
    "note_too_long" => "The note can be up to 300 characters.",
    "invalid_note" => "The note has characters that cannot be saved. Remove them.",
    "invalid_from" => "Type the pickup town only, like Pune.",
    "invalid_to" => "Type the drop town only, like Mumbai.",
    "invalid_weightKg" => "Check the weight.",
    "invalid_packages" => "Check the package sizes or the total volume.",
    _ => null,
  };
}

class PostALoadScreen extends StatefulWidget {
  const PostALoadScreen({required this.search, super.key});

  final LoadToPost search;

  @override
  State<PostALoadScreen> createState() => _PostALoadScreenState();
}

class _PostALoadScreenState extends State<PostALoadScreen> {
  late final _fromTown =
      TextEditingController(text: townToPost(widget.search.pickup));
  late final _toTown =
      TextEditingController(text: townToPost(widget.search.drop));
  late final _weightKg =
      TextEditingController(text: "${widget.search.weightKg}");
  final _count = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _volume = TextEditingController();
  final _note = TextEditingController();
  _SizeKind? _sizeKind;
  String? _sideUnit;
  String? _volumeUnit;
  late DateTime _firstPickupDay = todayInIndia();
  late DateTime _lastPickupDay = _firstPickupDay;
  bool _posting = false;
  String? _error;
  final _form = ScrollController();

  @override
  void dispose() {
    for (final field in [
      _fromTown,
      _toTown,
      _weightKg,
      _count,
      _length,
      _width,
      _height,
      _volume,
      _note
    ]) {
      field.dispose();
    }
    _form.dispose();
    super.dispose();
  }

  num? _positive(TextEditingController field, num max) {
    final value = num.tryParse(field.text.trim());
    return value != null && value > 0 && value <= max ? value : null;
  }

  /// The size as the server reads it, or null while something is missing or out of range.
  Map<String, dynamic>? get _packages {
    if (_sizeKind == _SizeKind.sizes) {
      final count = int.tryParse(_count.text.trim());
      final sides = [_length, _width, _height]
          .map((side) => _positive(side, _maxPackageSide))
          .toList();
      if (count == null ||
          count < 1 ||
          count > _maxPackageCount ||
          sides.contains(null) ||
          _sideUnit == null) {
        return null;
      }
      return {
        "kind": "SIZES",
        "count": count,
        "length": sides[0],
        "width": sides[1],
        "height": sides[2],
        "unit": _sideUnit,
      };
    }
    if (_sizeKind == _SizeKind.totalVolume) {
      final volume = _positive(_volume, _maxTotalVolume);
      if (volume == null || _volumeUnit == null) return null;
      return {"kind": "TOTAL_VOLUME", "volume": volume, "unit": _volumeUnit};
    }
    return null;
  }

  /// What still has to be filled in, or null.
  String? _missing() {
    final from = _fromTown.text.trim();
    final to = _toTown.text.trim();
    if (from.isEmpty || from.length > _maxTownLength) {
      return "Enter the pickup town.";
    }
    if (to.isEmpty || to.length > _maxTownLength) return "Enter the drop town.";
    final weight = int.tryParse(_weightKg.text.trim()) ?? 0;
    if (weight <= 0) return "Enter a weight greater than 0 kg.";
    if (weight > maxWeightKg) return overMaxWeightSentence;
    if (_sizeKind == null) {
      return "Choose how to give the size: number and size, or total volume.";
    }
    if (_packages == null) {
      return _sizeKind == _SizeKind.sizes
          ? "Enter how many packages, the size of each, and inches or cm."
          : "Enter the total volume, and cubic feet or cubic metres.";
    }
    if (_note.text.trim().characters.length > _maxNoteLength) {
      return "The note can be up to 300 characters.";
    }
    return null;
  }

  void _showError(String message) {
    setState(() => _error = message);
    announce(context, message);
    if (_form.hasClients) {
      _form.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _chooseDay({required bool firstDay}) async {
    final today = todayInIndia();
    final earliest = firstDay ? today : _firstPickupDay;
    final latest = firstDay
        ? today.add(const Duration(days: _daysAheadForFirstPickup))
        : _firstPickupDay.add(const Duration(days: _daysInPickupWindow));
    final current = firstDay ? _firstPickupDay : _lastPickupDay;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(earliest)
          ? earliest
          : current.isAfter(latest)
              ? latest
              : current,
      firstDate: earliest,
      lastDate: latest,
    );
    if (picked == null || !mounted) return;
    final day = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      if (firstDay) {
        _firstPickupDay = day;
        // A last day before the new first day, or too long after it, no longer fits the rules.
        final lastAllowed =
            day.add(const Duration(days: _daysInPickupWindow));
        if (_lastPickupDay.isBefore(day) || _lastPickupDay.isAfter(lastAllowed)) {
          _lastPickupDay = day;
        }
      } else {
        _lastPickupDay = day;
      }
    });
  }

  Future<void> _post() async {
    if (_posting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final missing = _missing();
    if (missing != null) {
      _showError(missing);
      return;
    }
    final pickup = widget.search.pickup.point!;
    final drop = widget.search.drop.point!;
    final note = _note.text.trim();
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await api.post<Map<String, dynamic>>("/v1/posted-loads", data: {
        "from": {
          "city": _fromTown.text.trim(),
          "lat": pickup.latitude,
          "lng": pickup.longitude
        },
        "to": {
          "city": _toTown.text.trim(),
          "lat": drop.latitude,
          "lng": drop.longitude
        },
        "weightKg": int.parse(_weightKg.text.trim()),
        "packages": _packages,
        "earliestPickupDate": calendarDayText(_firstPickupDay),
        "latestPickupDate": calendarDayText(_lastPickupDay),
        if (note.isNotEmpty) "note": note,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Load posted. We tell you when a carrier adds a trip.")));
      context.go("/customer/loads");
    } catch (error) {
      if (mounted) {
        _showError(_refusalSentence(error) ??
            plainErrorSentence(
                error, "Could not post. Check your connection, then try again."));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Widget _day(String label, DateTime day, {required bool firstDay}) =>
      MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: NvText.bodyStrong),
            const SizedBox(height: 6),
            NvButton(
              label: formatDate(day, withYear: true),
              kind: NvButtonKind.secondary,
              onPressed:
                  _posting ? null : () => _chooseDay(firstDay: firstDay),
              disabledReason: _posting ? "Posting" : null,
              fullWidth: true,
            ),
          ],
        ),
      );

  List<Widget> _sizeFields() => switch (_sizeKind) {
        _SizeKind.sizes => [
            NvField(
                label: "Number of packages",
                controller: _count,
                keyboardType: TextInputType.number,
                readOnly: _posting),
            const SizedBox(height: NvSpace.s4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (index, (label, side)) in [
                ("Length", _length),
                ("Width", _width),
                ("Height", _height)
              ].indexed) ...[
                if (index > 0) const SizedBox(width: NvSpace.s2),
                Expanded(
                    child: NvField(
                        label: label,
                        controller: side,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        readOnly: _posting)),
              ],
            ]),
            const SizedBox(height: NvSpace.s3),
            NvChoiceChips<String>(
              label: "Size of each package in",
              options: const [
                NvChoice("INCHES", "Inches"),
                NvChoice("CENTIMETRES", "cm"),
              ],
              selected: _sideUnit,
              onChanged: (unit) => setState(() => _sideUnit = unit),
            ),
          ],
        _SizeKind.totalVolume => [
            NvField(
                label: "Total volume",
                controller: _volume,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                readOnly: _posting),
            const SizedBox(height: NvSpace.s3),
            NvChoiceChips<String>(
              label: "Volume in",
              options: const [
                NvChoice("CUBIC_FEET", "Cubic feet"),
                NvChoice("CUBIC_METRES", "Cubic metres"),
              ],
              selected: _volumeUnit,
              onChanged: (unit) => setState(() => _volumeUnit = unit),
            ),
          ],
        null => const [],
      };

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: NvSpace.s4);
    return CustomerScaffold(
      title: "Post a load",
      subtitle: "Carriers going your way can add a trip for it.",
      currentPath: "/customer/post-load",
      actionBar: NvActionBar(
        child: NvButton(
            label: "Post load",
            loading: _posting,
            loadingLabel: "Posting",
            fullWidth: true,
            onPressed: _post),
      ),
      bodyBuilder: (_) => ListView(
        controller: _form,
        padding: const EdgeInsets.symmetric(vertical: NvSpace.s3),
        children: [
          if (_error != null) ...[
            NvMessage(_error!, tone: NvMessageTone.problem),
            gap,
          ],
          NvField(
              label: "Pickup town",
              controller: _fromTown,
              help:
                  "Carriers on the Load Board see what you type here. Type the town only, not your street address.",
              readOnly: _posting),
          gap,
          NvField(
              label: "Drop town",
              controller: _toTown,
              help:
                  "Carriers on the Load Board see what you type here. Type the town only, not your street address.",
              readOnly: _posting),
          gap,
          NvField(
              label: "Weight",
              controller: _weightKg,
              unit: "kg",
              keyboardType: TextInputType.number,
              readOnly: _posting),
          gap,
          NvChoiceChips<_SizeKind>(
            label: "Size",
            options: const [
              NvChoice(_SizeKind.sizes, "Number and size"),
              NvChoice(_SizeKind.totalVolume, "Total volume"),
            ],
            selected: _sizeKind,
            onChanged: (kind) => setState(() => _sizeKind = kind),
          ),
          if (_sizeKind != null) ...[gap, ..._sizeFields()],
          gap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: _day("First pickup day", _firstPickupDay,
                    firstDay: true)),
            const SizedBox(width: NvSpace.s3),
            Expanded(
                child:
                    _day("Last pickup day", _lastPickupDay, firstDay: false)),
          ]),
          const SizedBox(height: NvSpace.s2),
          const Text(
              "The first day can be up to 7 days ahead. The last can be up to 3 days after the first.",
              style: NvText.caption),
          gap,
          NvField(
              label: "Note",
              controller: _note,
              optional: true,
              help: "Only your company sees this note. Up to 300 characters.",
              readOnly: _posting),
          gap,
          const Text(
              "No price yet. You see the price when you book a trip a carrier adds.",
              style: NvText.caption),
        ],
      ),
    );
  }
}
