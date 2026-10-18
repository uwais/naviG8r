import "../pilot_api.dart";
import "../ui/format.dart";

String laneRoute(Map<String, dynamic> lane) =>
    "${lane["originCity"]} to ${lane["destCity"]}";

/// Capacity minus what is already booked, or null when the lane does not say.
num? roomLeftKg(Map<String, dynamic> lane) {
  final capacity = lane["capacityKg"];
  final reserved = lane["reservedKg"];
  if (capacity is! num || reserved is! num) return null;
  final room = capacity - reserved;
  return room < 0 ? 0 : room;
}

String roomLeftWords(num room) => room == 0 ? "None" : formatKg(room);

String? laneDates(Map<String, dynamic> lane) {
  final start = DateTime.tryParse(lane["windowStart"]?.toString() ?? "");
  final end = DateTime.tryParse(lane["windowEnd"]?.toString() ?? "");
  if (start == null && end == null) return null;
  return formatDateRange(start ?? end!, end ?? start!);
}

/// Every lane the trips list returns, by id, so a list of shipments can name each by its lane's
/// route and date and tell a started trip apart: one request, not one per shipment. A lane the
/// list no longer has leaves its shipment named by the pickup and drop as typed.
Future<Map<String, Map<String, dynamic>>> loadLanesById() async {
  try {
    final r = await api.get<Map<String, dynamic>>("/anchor-trips");
    final raw = r.data?["trips"];
    return {
      if (raw is List)
        for (final lane in raw.whereType<Map<String, dynamic>>())
          if ((lane["id"]?.toString() ?? "").isNotEmpty)
            lane["id"].toString(): lane,
    };
  } catch (_) {
    return {};
  }
}

Map<String, dynamic>? laneOfShipment(Map<String, dynamic> shipment,
        Map<String, Map<String, dynamic>> lanesById) =>
    lanesById[shipment["anchorTripId"]?.toString()];

/// "Bengaluru to Chennai, 18 Oct" from the shipment's lane, else its pickup and drop as typed;
/// never its ID (spec/copy.md, "Shipment name"). Null when neither is known.
String? shipmentRouteName(Map<String, dynamic> shipment,
    {Map<String, dynamic>? lane, bool withDate = true}) {
  final from = lane?["originCity"]?.toString() ?? "";
  final to = lane?["destCity"]?.toString() ?? "";
  if (from.isNotEmpty && to.isNotEmpty) {
    final start = DateTime.tryParse(lane?["windowStart"]?.toString() ?? "");
    return withDate && start != null
        ? shipmentName(from: from, to: to, date: start)
        : "$from to $to";
  }
  final pickup = shipment["pickupAddress"]?.toString() ?? "";
  final drop = shipment["dropAddress"]?.toString() ?? "";
  return pickup.isEmpty || drop.isEmpty ? null : "$pickup to $drop";
}

String? laneStartWords(Map<String, dynamic>? lane) {
  final start = DateTime.tryParse(lane?["windowStart"]?.toString() ?? "");
  return start == null ? null : formatDate(start);
}

String? weightWords(Map<String, dynamic> shipment) {
  final weight = shipment["weightKg"];
  return weight is num ? formatKg(weight) : null;
}

String carrierOf(Map<String, dynamic> shipment) {
  final name = shipment["carrierDisplayName"]?.toString() ?? "";
  return name.trim().isEmpty ? "The carrier" : name;
}

String shipmentCount(int count) =>
    count == 1 ? "1 shipment" : "$count shipments";
