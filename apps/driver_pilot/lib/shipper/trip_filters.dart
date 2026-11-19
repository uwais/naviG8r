// Search and filters over the trips Book a trip already has: All trips, and the results of Search by route.
// Neither list is paged, so filtering here sees every trip the server sent. Nothing here ranks a trip: each
// list keeps its own order, and the chips come from the trips themselves, carriers A to Z and sizes small to
// large.
import "package:flutter/material.dart";

import "../ui/format.dart";
import "../ui/nv_button.dart";
import "../ui/nv_choice.dart";
import "../ui/nv_field.dart";
import "../ui/nv_list_card.dart";
import "../ui/tokens.dart";

const _indiaOffset = Duration(hours: 5, minutes: 30);

const _truckSizes = [
  NvChoice<String?>("SMALL", "Small"),
  NvChoice<String?>("MEDIUM", "Medium"),
  NvChoice<String?>("LARGE", "Large"),
];

/// The date in India of an instant, as UTC midnight of that date: formatDate reads it back as the same date
/// in any phone zone, which a local midnight east of India would not be.
DateTime _indiaDate(DateTime moment) {
  final india = moment.toUtc().add(_indiaOffset);
  return DateTime.utc(india.year, india.month, india.day);
}

/// The last day the truck can leave, in India, or its first day when the trip gives no last one.
DateTime? _lastLeavingDay(Map<String, dynamic> trip) {
  final moment = DateTime.tryParse(trip["windowEnd"]?.toString() ?? "") ??
      DateTime.tryParse(trip["windowStart"]?.toString() ?? "");
  return moment == null ? null : _indiaDate(moment);
}

String _carrierOf(Map<String, dynamic> trip) =>
    trip["carrierDisplayName"]?.toString().trim() ?? "";

/// All trips, soonest to leave first. A trip with no dates goes last; trips leaving together keep the
/// order the server sent them in.
List<Map<String, dynamic>> soonestToLeaveFirst(
    List<Map<String, dynamic>> trips) {
  DateTime? start(Map<String, dynamic> trip) =>
      DateTime.tryParse(trip["windowStart"]?.toString() ?? "");
  final indexed = [for (final (index, trip) in trips.indexed) (index, trip)];
  indexed.sort((a, b) {
    final first = start(a.$2);
    final second = start(b.$2);
    if (first != null && second != null && first != second) {
      return first.compareTo(second);
    }
    if (first == null && second != null) return 1;
    if (first != null && second == null) return -1;
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, trip) in indexed) trip];
}

/// What the shipper has narrowed a list of trips to. Every filter starts off.
class TripFilters extends ChangeNotifier {
  TripFilters() {
    townWords.addListener(notifyListeners);
  }

  /// Matches the town a trip leaves from or goes to.
  final townWords = TextEditingController();
  DateTime? _leavesOnOrAfter;
  String? _carrier;
  String? _truckSize;

  /// A plain date in India: the trip must be able to leave on this day or later.
  DateTime? get leavesOnOrAfter => _leavesOnOrAfter;
  String? get carrier => _carrier;
  String? get truckSize => _truckSize;

  set leavesOnOrAfter(DateTime? day) {
    _leavesOnOrAfter = day;
    notifyListeners();
  }

  set carrier(String? name) {
    _carrier = name;
    notifyListeners();
  }

  set truckSize(String? size) {
    _truckSize = size;
    notifyListeners();
  }

  String get _words => townWords.text.trim().toLowerCase();

  bool get anyOn =>
      _words.isNotEmpty ||
      _leavesOnOrAfter != null ||
      _carrier != null ||
      _truckSize != null;

  void clearAll() {
    _leavesOnOrAfter = null;
    _carrier = null;
    _truckSize = null;
    // Clearing the words tells the listeners too.
    if (townWords.text.isEmpty) {
      notifyListeners();
    } else {
      townWords.clear();
    }
  }

  bool _keeps(Map<String, dynamic> trip) {
    final words = _words;
    if (words.isNotEmpty) {
      final from = trip["originCity"]?.toString().toLowerCase() ?? "";
      final to = trip["destCity"]?.toString().toLowerCase() ?? "";
      if (!from.contains(words) && !to.contains(words)) return false;
    }
    final day = _leavesOnOrAfter;
    if (day != null) {
      final lastDay = _lastLeavingDay(trip);
      if (lastDay == null || lastDay.isBefore(day)) return false;
    }
    if (_carrier != null && _carrierOf(trip) != _carrier) return false;
    if (_truckSize != null && trip["vehicleClass"] != _truckSize) return false;
    return true;
  }

  /// The trips every filter keeps, in the order given.
  List<Map<String, dynamic>> apply(List<Map<String, dynamic>> trips) =>
      trips.where(_keeps).toList();

  /// What to change when nothing is left, from the filters that are on.
  String get whatToChange {
    final changes = [
      if (_words.isNotEmpty) "other town words",
      if (_leavesOnOrAfter != null) "an earlier day",
      if (_carrier != null) "any carrier",
      if (_truckSize != null) "any truck size",
    ];
    final joined = changes.length < 2
        ? changes.join()
        : "${changes.sublist(0, changes.length - 1).join(", ")} or ${changes.last}";
    return "Try $joined, or clear all filters.";
  }

  @override
  void dispose() {
    townWords.dispose();
    super.dispose();
  }
}

/// The search box, the day, and the carrier and truck size chips, over [trips]: the list the screen loaded,
/// before any filter, so a chip does not vanish once chosen.
class TripFilterBar extends StatelessWidget {
  const TripFilterBar({required this.filters, required this.trips, super.key});
  final TripFilters filters;
  final List<Map<String, dynamic>> trips;

  Future<void> _chooseDay(BuildContext context) async {
    final today = _indiaDate(DateTime.now());
    final current = filters.leavesOnOrAfter;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(today) ? current : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: "Leaves on or after",
    );
    if (picked == null) return;
    filters.leavesOnOrAfter =
        DateTime.utc(picked.year, picked.month, picked.day);
  }

  @override
  Widget build(BuildContext context) {
    final carriers = {
      for (final trip in trips)
        if (_carrierOf(trip).isNotEmpty) _carrierOf(trip),
      if (filters.carrier != null) filters.carrier!,
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final sizesShown = {
      for (final trip in trips) trip["vehicleClass"],
      filters.truckSize,
    };
    final sizes = [
      for (final size in _truckSizes)
        if (sizesShown.contains(size.value)) size
    ];
    final day = filters.leavesOnOrAfter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NvField(
          label: "Search towns",
          hint: "From or to, for example Chennai",
          controller: filters.townWords,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: NvSpace.s3),
        const Text("Leaves on or after", style: NvText.bodyStrong),
        const SizedBox(height: 6),
        NvButton(
          label: day == null ? "Any day" : formatDate(day, withYear: true),
          semanticsLabel: day == null
              ? "Leaves on or after: any day. Choose a day"
              : "Leaves on or after ${formatDate(day, withYear: true)}. Change the day",
          kind: NvButtonKind.secondary,
          onPressed: () => _chooseDay(context),
          fullWidth: true,
        ),
        // One choice is no choice, so a row shows only when the trips differ.
        if (carriers.length > 1) ...[
          const SizedBox(height: NvSpace.s3),
          NvChoiceChips<String?>(
            label: "Carrier",
            options: [
              const NvChoice<String?>(null, "Any carrier"),
              for (final name in carriers) NvChoice<String?>(name, name),
            ],
            selected: filters.carrier,
            onChanged: (name) => filters.carrier = name,
          ),
        ],
        if (sizes.length > 1) ...[
          const SizedBox(height: NvSpace.s3),
          NvChoiceChips<String?>(
            label: "Truck size",
            options: [const NvChoice<String?>(null, "Any size"), ...sizes],
            selected: filters.truckSize,
            onChanged: (size) => filters.truckSize = size,
          ),
        ],
        if (filters.anyOn) ...[
          const SizedBox(height: NvSpace.s3),
          NvButton(
              label: "Clear all filters",
              kind: NvButtonKind.quiet,
              onPressed: filters.clearAll),
        ],
      ],
    );
  }
}

/// "Showing 2 of 5 trips.", only while a filter is on.
Widget? tripFilterCount(TripFilters filters, int shown, int all) =>
    filters.anyOn
        ? Semantics(
            liveRegion: true,
            child: Text(
                "Showing $shown of $all ${all == 1 ? "trip" : "trips"}.",
                style: NvText.caption))
        : null;

/// Nothing is left once the filters are on: say what to change. Clear all filters sits just above, in the bar.
Widget tripFiltersEmpty(TripFilters filters) => Semantics(
    liveRegion: true,
    child: NvListEmpty(
        title: "No trips match these filters.", help: filters.whatToChange));
