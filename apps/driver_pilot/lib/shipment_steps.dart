/// The shipper's own next task on a shipment, from the step mapping in spec/screens.md, or null
/// when someone else acts next. Only rows the shipments list can decide are covered: the list
/// has no trip status and no stored "needs an e-way bill" answer (RECON gaps 1 and 3).
String? shipperTaskFor(Map<String, dynamic> shipment,
    {required bool canWriteBill, required bool canAddTruck}) {
  if (shipment["status"] != "BOOKED") return null;
  final bill = shipment["ewayBill"];
  // No bill on an accepted shipment is the mapping's nearest row, "needed, no bill".
  if (bill == null) return canWriteBill ? "Make the e-way bill" : null;
  if (bill is! Map || bill["kind"] != "BILL") return null;
  final check = bill["check"];
  // A flagged bill wins over a missing truck: the fix may change the bill the truck goes on.
  if (check is Map && check["result"] == "PROBLEM") {
    return canWriteBill ? "Fix the e-way bill" : null;
  }
  final truck = bill["truckNumber"];
  if (truck is! String || truck.trim().isEmpty) {
    return canAddTruck ? "Add the truck to the e-way bill" : null;
  }
  return null;
}
