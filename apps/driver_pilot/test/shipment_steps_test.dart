// The "Shipment step mapping" table in spec/screens.md, row by row, and the shipper's Home task
// that is read from it.
import 'package:driver_pilot/shipment_steps.dart';
import 'package:driver_pilot/ui/nv_status_label.dart';
import 'package:driver_pilot/ui/nv_step_list.dart';
import 'package:flutter_test/flutter_test.dart';

String? taskFor(Map<String, dynamic> shipment,
        {bool canWriteBill = true,
        bool canAddTruck = true,
        bool canAcceptDelivery = true}) =>
    shipperTaskFor(shipment,
        canWriteBill: canWriteBill,
        canAddTruck: canAddTruck,
        canAcceptDelivery: canAcceptDelivery);

const bill = {'kind': 'BILL', 'billNumber': '341200987654'};
const billWithTruck = {...bill, 'truckNumber': 'KA01AB1234'};
const notNeeded = {'kind': 'NOT_NEEDED', 'notNeededReason': 'GOODS_EXEMPT'};

Map<String, dynamic> shipment(String status,
        [Map<String, dynamic>? ewayBill]) =>
    {
      'status': status,
      'carrierDisplayName': 'Ravi Roadways',
      if (ewayBill != null) 'ewayBill': ewayBill,
    };

NvStepState stateOf(ShipmentProgress progress, ShipmentStepName name) =>
    progress.steps.firstWhere((step) => step.name == name).state;

void main() {
  group('the step mapping, row by row', () {
    test('awaiting acceptance, no answer: the carrier accepts (nearest row)',
        () {
      final progress = shipmentProgress(shipment('PENDING_CARRIER_ACCEPT'));
      expect(progress.current, ShipmentStepName.carrierAccepts,
          reason:
              'no stored "needs an e-way bill" answer (RECON gap 1), so the nearest row is "needed / not needed"');
      expect(progress.actor, ShipmentActor.carrier);
      expect(progress.next, 'Ravi Roadways accepts and names the truck',
          reason: 'screens.md Next: line, with the carrier named');
      expect(stateOf(progress, ShipmentStepName.carrierAccepts),
          NvStepState.waiting);
      expect(stateOf(progress, ShipmentStepName.ewayBill), NvStepState.later,
          reason: 'the bill is made once the carrier names the truck');
      expect(progress.statusWord, 'Waiting for carrier');
    });

    test('awaiting acceptance, not needed or a bill saved: the carrier accepts',
        () {
      for (final answer in [notNeeded, bill]) {
        final progress =
            shipmentProgress(shipment('PENDING_CARRIER_ACCEPT', answer));
        expect(progress.current, ShipmentStepName.carrierAccepts,
            reason:
                'screens.md row "Awaiting acceptance, needed / not needed"');
        expect(progress.actor, ShipmentActor.carrier);
        expect(progress.next, 'Ravi Roadways accepts and names the truck');
        expect(progress.task, isNull);
      }
      expect(
          shipmentProgress(shipment('PENDING_CARRIER_ACCEPT', notNeeded))
              .steps[2]
              .title,
          'E-way bill: not needed',
          reason: 'copy.md: the not-needed step says so in its title');
    });

    test('accepted, no bill: the shipper makes the e-way bill', () {
      final progress = shipmentProgress(shipment('BOOKED'));
      expect(progress.current, ShipmentStepName.ewayBill);
      expect(progress.actor, ShipmentActor.shipper);
      expect(progress.next, 'You make the e-way bill');
      expect(progress.task, 'Make the e-way bill');
      expect(stateOf(progress, ShipmentStepName.ewayBill), NvStepState.yours);
      expect(
          stateOf(progress, ShipmentStepName.carrierAccepts), NvStepState.done);
      expect(progress.statusWord, 'Accepted');
    });

    test('accepted, bill but no truck: the shipper adds it', () {
      final progress = shipmentProgress(shipment('BOOKED', bill));
      expect(progress.current, ShipmentStepName.ewayBill);
      expect(progress.actor, ShipmentActor.shipper);
      expect(progress.next, 'You add the truck to the e-way bill');
      expect(progress.task, 'Add the truck to the e-way bill');
      expect(progress.steps[2].who, 'You',
          reason:
              'owner decision 18 Oct 2026: the shipper adds the truck, the carrier only reads the bill');
    });

    test('accepted, bill and truck, not checked: NaviG8r staff check it', () {
      final progress = shipmentProgress(shipment('BOOKED', billWithTruck));
      expect(progress.current, ShipmentStepName.billCheck);
      expect(progress.actor, ShipmentActor.staff);
      expect(progress.next, 'NaviG8r staff check the bill');
      expect(progress.task, isNull);
      expect(stateOf(progress, ShipmentStepName.ewayBill), NvStepState.done);
      expect(
          stateOf(progress, ShipmentStepName.billCheck), NvStepState.waiting);
    });

    test('accepted, staff found a problem: the shipper fixes the bill', () {
      final progress = shipmentProgress(shipment('BOOKED', {
        ...billWithTruck,
        'check': {'result': 'PROBLEM', 'problemReason': 'DETAILS_DO_NOT_MATCH'}
      }));
      expect(progress.current, ShipmentStepName.ewayBill);
      expect(progress.actor, ShipmentActor.shipper);
      expect(progress.next, 'You fix the e-way bill');
      expect(progress.task, 'Fix the e-way bill');
      expect(stateOf(progress, ShipmentStepName.ewayBill), NvStepState.problem);
      expect(progress.statusWord, 'E-way bill needs a fix');
      expect(progress.statusTone, NvStatusTone.problem);
    });

    test('a flagged bill wins over a missing truck', () {
      final progress = shipmentProgress(shipment('BOOKED', {
        ...bill,
        'check': {'result': 'PROBLEM'}
      }));
      expect(progress.ewayBill, EwayBillStage.problem,
          reason:
              'screens.md does not say (RECON gap 4); the fix may change the bill the truck goes on');
    });

    test('accepted, checked or not needed: the carrier starts the trip', () {
      for (final answer in [
        notNeeded,
        {
          ...billWithTruck,
          'check': {'result': 'FOUND'}
        },
      ]) {
        final progress = shipmentProgress(shipment('BOOKED', answer));
        expect(progress.current, ShipmentStepName.onTheWay);
        expect(progress.actor, ShipmentActor.carrier);
        expect(progress.next, 'Ravi Roadways starts the trip');
        expect(
            stateOf(progress, ShipmentStepName.onTheWay), NvStepState.waiting);
        expect(stateOf(progress, ShipmentStepName.ewayBill), NvStepState.done);
      }
    });

    test('in transit, any bill: the carrier confirms delivery', () {
      for (final answer in [null, bill, notNeeded]) {
        final progress = shipmentProgress(shipment('BOOKED', answer),
            tripStatus: 'IN_PROGRESS');
        expect(progress.current, ShipmentStepName.onTheWay);
        expect(progress.actor, ShipmentActor.carrier);
        expect(progress.next, 'Ravi Roadways confirms delivery');
        expect(progress.statusWord, 'In transit');
        expect(progress.task, isNull);
      }
      expect(shipmentProgress(shipment('BOOKED', notNeeded)).inTransit, isFalse,
          reason:
              'without the trip there is no in-transit status on a shipment (RECON gap 3)');
    });

    test('delivery confirmed or delivered: every step done, nothing next', () {
      for (final status in ['PENDING_RELEASE', 'DELIVERED']) {
        final progress = shipmentProgress(shipment(status, billWithTruck));
        expect(progress.current, ShipmentStepName.delivered, reason: status);
        expect(progress.actor, ShipmentActor.nobody);
        expect(progress.next, isNull);
        expect(progress.statusWord, 'Delivered');
        expect(progress.steps.every((step) => step.state == NvStepState.done),
            isTrue,
            reason: '$status: all done');
      }
    });

    test('cancelled: no steps, nothing next, and a word, never the code', () {
      final progress = shipmentProgress(shipment('FAILED_CARRIER_REFUNDED'));
      expect(progress.steps, isEmpty);
      expect(progress.cancelled, isTrue);
      expect(progress.next, isNull);
      expect(progress.statusWord, 'Cancelled',
          reason: 'copy.md: words, never the system code');
    });

    test('a status the app does not know still reads as a word', () {
      expect(shipmentProgress(shipment('SOMETHING_NEW')).statusWord, 'Booked',
          reason: 'decisions.md guardrail 7: no raw codes');
    });

    test('the steps come in the copy.md order', () {
      expect(
          shipmentProgress(shipment('BOOKED', billWithTruck))
              .steps
              .map((step) => step.title),
          [
            'Booked and paid',
            'Carrier accepts and names the truck',
            'E-way bill',
            'Bill check',
            'On the way',
            'Delivered'
          ]);
      expect(
          shipmentProgress(shipment('BOOKED', notNeeded))
              .steps
              .map((step) => step.title),
          isNot(contains('Bill check')),
          reason: 'only a saved bill is checked');
    });

    test('with no carrier name the line still reads', () {
      expect(shipmentProgress({'status': 'PENDING_CARRIER_ACCEPT'}).next,
          'The carrier accepts and names the truck');
    });
  });

  group('the Home task', () {
    test('accepted with no bill: the shipper makes the e-way bill', () {
      expect(taskFor({'status': 'BOOKED'}), 'Make the e-way bill',
          reason:
              'screens.md row "Accepted, needed, no bill", the nearest row');
    });

    test('a bill without the truck: add the truck', () {
      expect(taskFor({'status': 'BOOKED', 'ewayBill': bill}),
          'Add the truck to the e-way bill',
          reason: 'screens.md row "Accepted, bill, no truck"');
    });

    test('a flagged bill: fix it, even when the truck is also missing', () {
      expect(
          taskFor({
            'status': 'BOOKED',
            'ewayBill': {
              ...bill,
              'check': {'result': 'PROBLEM'}
            }
          }),
          'Fix the e-way bill',
          reason: 'screens.md row "Accepted, ops problem"');
    });

    test('nothing for the shipper while someone else acts', () {
      expect(taskFor({'status': 'PENDING_CARRIER_ACCEPT'}), isNull,
          reason:
              'the step-0 answer has no stored field, so it is not a Home task');
      expect(taskFor({'status': 'BOOKED', 'ewayBill': billWithTruck}), isNull,
          reason: 'bill and truck saved: NaviG8r staff check it');
      expect(taskFor({'status': 'BOOKED', 'ewayBill': notNeeded}), isNull,
          reason: 'not needed: the carrier starts the trip');
      for (final status in [
        'PENDING_RELEASE',
        'DELIVERED',
        'FAILED_CARRIER_REFUNDED'
      ]) {
        expect(taskFor({'status': status}), isNull,
            reason: '$status needs nothing from the shipper');
      }
    });

    test('a task the login may not do is not offered', () {
      expect(taskFor({'status': 'BOOKED'}, canWriteBill: false), isNull,
          reason: 'no eway_bill.write, no bill to make');
      expect(
          taskFor({'status': 'BOOKED', 'ewayBill': bill}, canAddTruck: false),
          isNull,
          reason: 'no eway_bill.add_truck, no truck task');
      expect(taskFor(awaitingAcceptance, canAcceptDelivery: false), isNull,
          reason: 'no pod.accept, no delivery to accept');
    });

    test('delivery confirmed and not yet accepted: the shipper accepts it', () {
      final progress = shipmentProgress(awaitingAcceptance);
      expect(progress.actor, ShipmentActor.shipper);
      expect(progress.next, 'You accept the delivery',
          reason: 'the list Next: line on the delivered card');
      expect(taskFor(awaitingAcceptance), 'Accept delivery',
          reason: 'seen on the recorded run: Home showed no delivery task');
      expect(
          taskFor({...awaitingAcceptance, 'podAcceptedAtUtcMs': 2}), isNull,
          reason: 'once accepted, nothing is left for the shipper');
    });

    test('the 48-hour hold is over: nothing is left for the shipper', () {
      final holdOver = {...awaitingAcceptance, 'paymentReady': true};
      final progress = shipmentProgress(holdOver);
      expect(progress.actor, ShipmentActor.nobody);
      expect(progress.next, isNull,
          reason: 'accepting no longer changes when payment is released');
      expect(taskFor(holdOver), isNull,
          reason: 'review: a delivery from three days ago stayed first on Home');
    });
  });
}

/// The driver confirmed delivery and the payment is on hold.
final awaitingAcceptance = {
  ...shipment('PENDING_RELEASE', billWithTruck),
  'podAtUtcMs': 1,
};
