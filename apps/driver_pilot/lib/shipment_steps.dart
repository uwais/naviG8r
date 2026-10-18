import "shipper/shipper_words.dart" show carrierOf;
import "ui/nv_status_label.dart" show NvStatusTone;
import "ui/nv_step_list.dart" show NvStepState;

// The shipper's view of one shipment: the "Shipment step mapping" in spec/screens.md, worked out
// from the booking status, the e-way bill and, where the screen has it, the trip's status. The
// shipment screen, the shipments list "Next:" line and the Home "Needs you" card all read this.

/// Who acts on the current step.
enum ShipmentActor { shipper, carrier, shipperOrCarrier, staff, nobody }

/// Where the shipper's e-way bill stands. There is no stored "yes, it needs one" answer, so
/// no bill at all is [none] (RECON gap 1).
enum EwayBillStage {
  none,
  notNeeded,
  billWithoutTruck,
  awaitingCheck,
  problem,
  checked
}

enum ShipmentStepName {
  booked,
  carrierAccepts,
  ewayBill,
  billCheck,
  onTheWay,
  delivered
}

class ShipmentStep {
  const ShipmentStep(this.name, this.title, this.state, {this.who});
  final ShipmentStepName name;
  final String title;
  final NvStepState state;

  /// Who does the step: "You", the carrier's name, "NaviG8r staff".
  final String? who;
}

class ShipmentProgress {
  const ShipmentProgress({
    required this.steps,
    required this.current,
    required this.actor,
    required this.next,
    required this.task,
    required this.statusWord,
    required this.statusTone,
    required this.ewayBill,
    required this.inTransit,
  });

  /// Empty for a cancelled shipment, which shows no steps.
  final List<ShipmentStep> steps;
  final ShipmentStepName? current;
  final ShipmentActor actor;

  /// The words after "Next:" on a list card, or null when nothing more happens.
  final String? next;

  /// The shipper's own task, such as "Make the e-way bill", or null when someone else acts.
  final String? task;
  final String statusWord;
  final NvStatusTone statusTone;
  final EwayBillStage ewayBill;
  final bool inTransit;

  /// A cancelled shipment is the only one with no steps.
  bool get cancelled => steps.isEmpty;
  bool get delivered => current == ShipmentStepName.delivered;
}

EwayBillStage ewayBillStageOf(Map<String, dynamic> shipment) {
  final bill = shipment["ewayBill"];
  if (bill is! Map) return EwayBillStage.none;
  if (bill["kind"] == "NOT_NEEDED") return EwayBillStage.notNeeded;
  if (bill["kind"] != "BILL") return EwayBillStage.none;
  final check = bill["check"];
  // A flagged bill wins over a missing truck: the fix may change the bill the truck goes on (RECON gap 4).
  if (check is Map && check["result"] == "PROBLEM") {
    return EwayBillStage.problem;
  }
  final truck = bill["truckNumber"];
  if (truck is! String || truck.trim().isEmpty) {
    return EwayBillStage.billWithoutTruck;
  }
  if (check is Map && check["result"] == "FOUND") return EwayBillStage.checked;
  return EwayBillStage.awaitingCheck;
}

/// A booking is made before checkout, so a closed or failed checkout leaves it booked and unpaid.
bool paymentNotTaken(String? paymentStatus) =>
    paymentStatus == "CREATED" || paymentStatus == "FAILED";

/// [tripStatus] is the trip's status when the screen loaded the trip; without it a started trip
/// reads as not started yet. [paymentStatus] is the payment's status where the screen has it; the
/// list cards do not (RECON gap 16).
ShipmentProgress shipmentProgress(Map<String, dynamic> shipment,
    {String? tripStatus, String? paymentStatus}) {
  final status = shipment["status"]?.toString() ?? "";
  final carrier = carrierOf(shipment);
  final unpaid = paymentNotTaken(paymentStatus);
  final stage = ewayBillStageOf(shipment);
  final waitingForCarrier = status == "PENDING_CARRIER_ACCEPT";
  final delivered = status == "PENDING_RELEASE" || status == "DELIVERED";
  final inTransit = status == "BOOKED" &&
      (tripStatus == "IN_PROGRESS" || tripStatus == "COMPLETED");

  if (status == "FAILED_CARRIER_REFUNDED") {
    return ShipmentProgress(
        steps: const [],
        current: null,
        actor: ShipmentActor.nobody,
        next: null,
        task: null,
        statusWord: "Cancelled",
        statusTone: NvStatusTone.ended,
        ewayBill: stage,
        inTransit: false);
  }

  final (ShipmentStepName current, ShipmentActor actor, String? next) =
      switch (stage) {
    _ when delivered => (
        ShipmentStepName.delivered,
        ShipmentActor.nobody,
        null
      ),
    _ when inTransit => (
        ShipmentStepName.onTheWay,
        ShipmentActor.carrier,
        "$carrier confirms delivery"
      ),
    // No stored answer to the step-0 question, so the nearest row is "needed / not needed".
    _ when waitingForCarrier || status != "BOOKED" => (
        ShipmentStepName.carrierAccepts,
        ShipmentActor.carrier,
        "$carrier accepts and names the truck"
      ),
    EwayBillStage.none => (
        ShipmentStepName.ewayBill,
        ShipmentActor.shipper,
        "You make the e-way bill"
      ),
    EwayBillStage.billWithoutTruck => (
        ShipmentStepName.ewayBill,
        ShipmentActor.shipperOrCarrier,
        "Add the truck to the e-way bill"
      ),
    EwayBillStage.awaitingCheck => (
        ShipmentStepName.billCheck,
        ShipmentActor.staff,
        "NaviG8r staff check the bill"
      ),
    EwayBillStage.problem => (
        ShipmentStepName.ewayBill,
        ShipmentActor.shipper,
        "You fix the e-way bill"
      ),
    EwayBillStage.checked || EwayBillStage.notNeeded => (
        ShipmentStepName.onTheWay,
        ShipmentActor.carrier,
        "$carrier starts the trip"
      ),
  };

  final task =
      actor == ShipmentActor.shipper || actor == ShipmentActor.shipperOrCarrier
          ? switch (stage) {
              EwayBillStage.none => "Make the e-way bill",
              EwayBillStage.billWithoutTruck =>
                "Add the truck to the e-way bill",
              EwayBillStage.problem => "Fix the e-way bill",
              _ => null,
            }
          : null;

  final (String statusWord, NvStatusTone statusTone) = switch (status) {
    _ when delivered => ("Delivered", NvStatusTone.good),
    _ when unpaid => ("Not paid", NvStatusTone.problem),
    _ when stage == EwayBillStage.problem => (
        "E-way bill needs a fix",
        NvStatusTone.problem
      ),
    _ when inTransit => ("In transit", NvStatusTone.info),
    "PENDING_CARRIER_ACCEPT" => ("Waiting for carrier", NvStatusTone.attention),
    "BOOKED" => ("Accepted", NvStatusTone.info),
    // A status this app does not know yet still reads as a word, never as its code.
    _ => ("Booked", NvStatusTone.info),
  };

  NvStepState stateWhen(bool done, {bool inProgress = false}) => done
      ? NvStepState.done
      : (inProgress ? NvStepState.waiting : NvStepState.later);

  final ewayBillState = switch (stage) {
    _ when delivered => NvStepState.done,
    EwayBillStage.notNeeded ||
    EwayBillStage.awaitingCheck ||
    EwayBillStage.checked =>
      NvStepState.done,
    EwayBillStage.problem => NvStepState.problem,
    EwayBillStage.none ||
    EwayBillStage.billWithoutTruck =>
      waitingForCarrier ? NvStepState.later : NvStepState.yours,
  };

  return ShipmentProgress(
    steps: [
      unpaid
          ? const ShipmentStep(
              ShipmentStepName.booked, "Booked, not paid", NvStepState.problem)
          : const ShipmentStep(
              ShipmentStepName.booked, "Booked and paid", NvStepState.done),
      ShipmentStep(
          ShipmentStepName.carrierAccepts,
          "Carrier accepts and names the truck",
          stateWhen(!waitingForCarrier, inProgress: true),
          who: carrier),
      ShipmentStep(
          ShipmentStepName.ewayBill,
          stage == EwayBillStage.notNeeded
              ? "E-way bill: not needed"
              : "E-way bill",
          ewayBillState,
          who: stage == EwayBillStage.billWithoutTruck
              ? "You or $carrier"
              : "You"),
      // Only a saved bill is checked; a flagged one is fixed on the e-way bill step first.
      if (stage == EwayBillStage.awaitingCheck ||
          stage == EwayBillStage.checked)
        ShipmentStep(
            ShipmentStepName.billCheck,
            "Bill check",
            stateWhen(stage == EwayBillStage.checked || delivered,
                inProgress: true),
            who: "NaviG8r staff"),
      ShipmentStep(
          ShipmentStepName.onTheWay,
          "On the way",
          stateWhen(delivered,
              inProgress: inTransit || current == ShipmentStepName.onTheWay),
          who: carrier),
      ShipmentStep(
          ShipmentStepName.delivered, "Delivered", stateWhen(delivered),
          who: carrier),
    ],
    current: current,
    actor: actor,
    next: next,
    task: task,
    statusWord: statusWord,
    statusTone: statusTone,
    ewayBill: stage,
    inTransit: inTransit,
  );
}

/// The shipper's Home task on a shipment, or null when someone else acts next or this login may
/// not do it.
String? shipperTaskFor(Map<String, dynamic> shipment,
    {required bool canWriteBill,
    required bool canAddTruck,
    String? tripStatus}) {
  final task = shipmentProgress(shipment, tripStatus: tripStatus).task;
  if (task == "Add the truck to the e-way bill") {
    return canAddTruck ? task : null;
  }
  return canWriteBill ? task : null;
}
