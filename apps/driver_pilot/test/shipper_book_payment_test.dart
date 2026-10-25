// PR 4 of the redesign: Book and pay, from the one tap to the payment partner and back, and the
// lines beside the button (sh-book-*). Names, places and amounts are the mockups' synthetic ones.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/ui/nv_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';
import 'support/shipper_lanes_app.dart';
import 'support/shipper_screen_checks.dart';

void main() {
  group('Book', () {
    testWidgets('while the booking is sent, weight and both places cannot change',
        (tester) async {
      final answer = Completer<ResponseBody>();
      final server = await showPricedBook(tester);
      server.answers['/shipments/book'] = (_) => answer.future;
      await tester.tap(find.text('Book and pay ₹2,640'));
      await pumpWhileWaiting(tester);
      expect(tester.widget<TextField>(field('Weight')).readOnly, isTrue,
          reason: 'reviewer: the form could change under a booking being sent');
      for (final title in ['Pickup', 'Drop']) {
        expect(tester.widget<TextField>(placeField(title)).readOnly, isTrue,
            reason: '$title cannot be typed in');
        expect(
            tester
                .widget<IconButton>(find.descendant(
                    of: placeBox(title), matching: find.byType(IconButton)))
                .onPressed,
            isNull,
            reason: '$title cannot be searched');
        expect(pinIn(tester, title).draggable, isFalse,
            reason: 'the $title pin cannot be dragged');
      }

      answer.complete(jsonResponse({'error': 'internal_error'}, 500));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Weight')).readOnly, isFalse,
          reason: 'after a failed booking the form can be changed again');
      expect(pinIn(tester, 'Drop').draggable, isTrue);
    });

    testWidgets('a fast second tap on Book and pay sends one booking',
        (tester) async {
      final answer = Completer<ResponseBody>();
      final server = await showPricedBook(tester);
      server.answers['/shipments/book'] = (_) => answer.future;
      final pay = find.text('Book and pay ₹2,640');
      await tester.tap(pay);
      await tester.tap(pay);
      await pumpWhileWaiting(tester);
      expect(server.countOf('/shipments/book'), 1,
          reason: 'review: a double tap before the button redrew booked twice');
      answer.complete(jsonResponse({'error': 'internal_error'}, 500));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'while a paid checkout is being confirmed, Book and pay stays busy and a second tap books nothing',
        (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('razorpay_flutter'), (call) async {
        return call.method == 'open'
            ? {
                'type': 0,
                'data': {
                  'razorpay_payment_id': 'pay_synthetic',
                  'razorpay_order_id': 'order_synthetic',
                  'razorpay_signature': 'signature_synthetic'
                }
              }
            : null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('razorpay_flutter'), null));
      final confirm = Completer<ResponseBody>();
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {
          'status': 'CREATED',
          'amountPaise': 264000,
          'razorpayOrderId': 'order_synthetic'
        },
        'razorpayKeyId': 'rzp_test_synthetic',
      });
      server.answers['/v1/payments/razorpay/confirm'] = (_) => confirm.future;
      await tester.tap(find.text('Book and pay ₹2,640'));
      await pumpWhileWaiting(tester);
      expect(server.countOf('/v1/payments/razorpay/confirm'), 1,
          reason: 'the checkout came back paid and the confirm is out');
      expect(bookButton(tester).loading, isTrue,
          reason: 'hunt, 23 Oct 2026: the button came back while the confirm was out');
      await tester.tap(find.text('Book and pay ₹2,640'), warnIfMissed: false);
      await pumpWhileWaiting(tester);
      expect(server.countOf('/shipments/book'), 1,
          reason: 'a second tap booked and charged a second shipment');
      confirm.complete(jsonResponse({'payment': {'status': 'AUTHORIZED'}}));
      await tester.pumpAndSettle();
      expect(find.text('Shipment shipment-9'), findsOneWidget,
          reason: 'once confirmed, the shipment opens');
    });

    testWidgets('Pay opens payment in one tap, with no sheet first',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CAPTURED', 'amountPaise': 264000},
      });
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(find.byType(NvSheet), findsNothing,
          reason: 'Rishabh: from a filled form, paying is one tap');
      expect(server.countOf('/shipments/book'), 1,
          reason: 'the one tap runs the existing booking call');
      final booked = server.sentTo('/shipments/book').single;
      expect(booked['weightKg'], 80, reason: 'the priced weight is booked');
      expect(booked['pickupAddress'], 'Bommasandra, Bengaluru');
      expect(find.text('Shipment shipment-9'), findsOneWidget,
          reason: 'after booking, the shipment opens');
    });

    testWidgets('one tap on Pay opens the payment provider with the amount',
        (tester) async {
      final opened = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('razorpay_flutter'), (call) async {
        if (call.method == 'open') opened.add(call.arguments as Map);
        return call.method == 'open'
            ? {
                'type': 1,
                'data': {'code': 2, 'message': 'Payment cancelled'}
              }
            : null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('razorpay_flutter'), null));
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {
          'status': 'CREATED',
          'amountPaise': 264000,
          'razorpayOrderId': 'order_synthetic'
        },
        'razorpayKeyId': 'rzp_test_synthetic',
      });
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1),
          reason: 'Rishabh: Pay goes straight to the payment step');
      expect(opened.single.toString(), contains('264000'),
          reason: 'the provider is opened for the amount on Pay');
    });

    testWidgets(
        'too heavy shows the plain sentence under Weight, never HTTP text',
        (tester) async {
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {'error': 'insufficient_capacity'}, 400);
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'This trip does not have enough capacity for that weight. Enter less weight, or choose another trip.'),
          findsOneWidget,
          reason: 'copy.md: too heavy, replaces "HTTP 400"');
      expect(find.textContaining('HTTP'), findsNothing,
          reason: 'decisions.md 7: no raw codes');
      expect(find.text('Choose another trip'), findsOneWidget,
          reason: 'copy.md: the way to another lane');
    });

    testWidgets('after a no-capacity refusal, the trip is loaded again and its capacity is current',
        (tester) async {
      final server = await showPricedBook(tester);
      expect(find.text('Capacity remaining: 25 kg'), findsOneWidget,
          reason: '105 kg left when the screen opened, less the 80 kg typed');
      final lanesBefore = server.countOf('/anchor-trips/lane-1');
      server.answer('/shipments/book', {'error': 'insufficient_capacity'}, 400);
      server.answer('/anchor-trips/lane-1', {'trip': lane(reservedKg: 950)});
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(server.countOf('/anchor-trips/lane-1'), lanesBefore + 1);
      expect(find.text("30 kg more than the capacity remaining"), findsOneWidget,
          reason: 'someone else booked 55 kg meanwhile: 50 kg are left, not 105');
    });

    // The booking exists before checkout opens, so after checkout the shipper goes to it and Pay is
    // never offered again: a second Pay would book a second shipment.
    Future<(FakeServer, List<String>)> payThroughCheckout(WidgetTester tester,
        {required Map<String, dynamic> checkoutAnswer,
        bool confirmFails = false,
        Map<String, dynamic>? confirmRefusal}) async {
      final announced = watchAnnouncements(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('razorpay_flutter'),
          (call) async => call.method == 'open' ? checkoutAnswer : null);
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('razorpay_flutter'), null));
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {
          'status': 'CREATED',
          'amountPaise': 264000,
          'razorpayOrderId': 'order_synthetic'
        },
        'razorpayKeyId': 'rzp_test_synthetic',
      });
      if (confirmFails) {
        server.answer(
            '/v1/payments/razorpay/confirm', {'error': 'internal_error'}, 500);
      }
      if (confirmRefusal != null) {
        server.answer('/v1/payments/razorpay/confirm', confirmRefusal, 409);
      }
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      return (server, announced);
    }

    testWidgets(
        'a closed or failed checkout opens the unpaid booking instead of offering Pay again',
        (tester) async {
      final (server, announced) =
          await payThroughCheckout(tester, checkoutAnswer: {
        'type': 1,
        'data': {'code': 2, 'message': 'Payment cancelled'}
      });
      expect(server.countOf('/shipments/book'), 1);
      expect(find.text('Shipment shipment-9'), findsOneWidget,
          reason:
              'the booking already exists; tapping Pay again would book a second shipment');
      expect(find.text('Payment did not go through. This shipment is not paid.'),
          findsOneWidget,
          reason: 'says why the shipment opened, in plain words');
      expect(find.textContaining('Payment cancelled'), findsNothing,
          reason: "the payment provider's own message is not shown");
      expect(announced,
          contains('Payment did not go through. This shipment is not paid.'),
          reason: 'never announce "Booked. Waiting" for an unpaid booking');
    });

    testWidgets(
        'a payment the app could not confirm opens the shipment without saying it is paid',
        (tester) async {
      final (_, announced) =
          await payThroughCheckout(tester, confirmFails: true, checkoutAnswer: {
        'type': 0,
        'data': {
          'razorpay_order_id': 'order_synthetic',
          'razorpay_payment_id': 'pay_synthetic',
          'razorpay_signature': 'signature_synthetic'
        }
      });
      expect(find.text('Shipment shipment-9'), findsOneWidget);
      expect(
          announced,
          contains(
              'Booked. We could not confirm the payment yet. The shipment shows whether it went through.'),
          reason:
              'the confirm call failed, so the app does not know the payment is held');
    });

    testWidgets(
        'a payment refused because the trip has left shows the server sentence, never Booked',
        (tester) async {
      const sentence = 'This trip has already left. If your bank shows a payment, it comes back within 3 days.';
      final (_, announced) = await payThroughCheckout(tester,
          confirmRefusal: const {'error': 'trip_already_started', 'detail': sentence},
          checkoutAnswer: {
            'type': 0,
            'data': {
              'razorpay_order_id': 'order_synthetic',
              'razorpay_payment_id': 'pay_synthetic',
              'razorpay_signature': 'signature_synthetic'
            }
          });
      expect(find.text(sentence), findsOneWidget,
          reason: 'owner, 23 Oct 2026: the app shows the server sentence');
      expect(announced, contains(sentence));
      expect(announced.where((words) => words.startsWith('Booked')), isEmpty,
          reason: 'the booking did not go ahead');
      expect(find.text('Shipment shipment-9'), findsOneWidget,
          reason: 'the shipment opens and says the trip left without it');
    });

    testWidgets(
        'a payment refused because the booking expired unpaid shows the server sentence, never Booked',
        (tester) async {
      const sentence = 'This booking expired because it was not paid within 30 minutes. If your bank shows a payment, it comes back within 3 days.';
      final (_, announced) = await payThroughCheckout(tester,
          confirmRefusal: const {'error': 'booking_expired', 'detail': sentence},
          checkoutAnswer: {
            'type': 0,
            'data': {
              'razorpay_order_id': 'order_synthetic',
              'razorpay_payment_id': 'pay_synthetic',
              'razorpay_signature': 'signature_synthetic'
            }
          });
      expect(find.text(sentence), findsOneWidget);
      expect(announced, contains(sentence));
      expect(announced.where((words) => words.startsWith('Booked')), isEmpty,
          reason: 'the booking did not go ahead');
    });

    testWidgets(
        'a booking whose payment never started is not announced as paid',
        (tester) async {
      final announced = watchAnnouncements(tester);
      final server = await showPricedBook(tester);
      server.answer('/shipments/book', {
        'shipment': {'id': 'shipment-9'},
        'payment': {'status': 'CREATED', 'amountPaise': 264000},
      });
      await tester.tap(find.text('Book and pay ₹2,640'));
      await tester.pumpAndSettle();
      expect(find.text('Shipment shipment-9'), findsOneWidget);
      expect(
          announced,
          contains(
              'Booked, but payment did not start. This shipment is not paid.'),
          reason: 'checkout never opened, so nothing was paid');
    });

    testWidgets(
        'Pay, the full-price line and the contact line are on screen without scrolling at 360 x 800',
        (tester) async {
      await showPricedBook(tester, height: 800);
      for (final words in ['Book and pay ₹2,640', fullPriceLine, contactAbovePay]) {
        final shown = tester.getRect(find.text(words));
        expect(shown.top >= 0 && shown.bottom <= 800, isTrue,
            reason:
                'decisions.md 8 and no hidden costs: "$words" shows beside Pay at 360 x 800');
      }
    });

    testWidgets(
        'Book and pay names the total, with the cancel line first in the words above it',
        (tester) async {
      await showPricedBook(tester);
      expect(bookButton(tester).label, 'Book and pay ₹2,640',
          reason: 'Rishabh: one tap books and opens payment, and the label says both');
      final button = tester.getRect(find.text('Book and pay ₹2,640'));
      final cancelLine = tester.getRect(find.text(contactAbovePay));
      final fullPrice = tester.getRect(find.text(fullPriceLine));
      expect(cancelLine.bottom, lessThanOrEqualTo(fullPrice.top),
          reason: 'first in the words, so it shows even when they scroll at large text');
      expect(fullPrice.bottom, lessThanOrEqualTo(button.top),
          reason: 'all the words sit above the button');
      expect(
          find.textContaining('If you close the payment screen'), findsNothing,
          reason: 'owner, 22 Oct 2026: a failed payment is said when it happens, not before');
    });

  });
}
