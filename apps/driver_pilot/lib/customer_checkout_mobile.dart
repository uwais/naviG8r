import "package:razorpay_flutter/razorpay_flutter.dart";

typedef CheckoutSuccess = void Function({
  required String orderId,
  required String paymentId,
  required String signature,
});

typedef CheckoutError = void Function(String message);

/// Mobile Razorpay checkout (Android/iOS).
class CustomerCheckoutController {
  CustomerCheckoutController({required this.onSuccess, required this.onError});

  final CheckoutSuccess onSuccess;
  final CheckoutError onError;

  Razorpay? _rzp;

  void init() {
    _rzp = Razorpay();
    _rzp!.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
      onSuccess(
        orderId: response.orderId ?? "",
        paymentId: response.paymentId ?? "",
        signature: response.signature ?? "",
      );
    });
    _rzp!.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      onError(response.message ?? "Payment failed.");
    });
  }

  void dispose() {
    _rzp?.clear();
    _rzp = null;
  }

  void open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String shipmentId,
  }) {
    final rzp = _rzp;
    if (rzp == null) {
      onError("Payment handler not ready.");
      return;
    }
    rzp.open({
      "key": keyId,
      "amount": amountPaise,
      "currency": "INR",
      "name": "NaviG8r",
      "description": "Authorize shipment payment",
      "order_id": orderId,
    });
  }
}
