import "dart:js" as js;

typedef CheckoutSuccess = void Function({
  required String orderId,
  required String paymentId,
  required String signature,
});

typedef CheckoutError = void Function(String message);

/// Web Razorpay Standard Checkout via checkout.js (see web/index.html).
class CustomerCheckoutController {
  CustomerCheckoutController({required this.onSuccess, required this.onError});

  final CheckoutSuccess onSuccess;
  final CheckoutError onError;

  void init() {}

  void dispose() {}

  void open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String shipmentId,
  }) {
    final RazorpayCtor = js.context["Razorpay"];
    if (RazorpayCtor is! js.JsFunction) {
      onError("Razorpay checkout.js not loaded. Refresh the page and try again.");
      return;
    }
    final handler = js.allowInterop((dynamic response) {
      if (response is! js.JsObject) {
        onError("Unexpected payment response.");
        return;
      }
      onSuccess(
        orderId: response["razorpay_order_id"]?.toString() ?? orderId,
        paymentId: response["razorpay_payment_id"]?.toString() ?? "",
        signature: response["razorpay_signature"]?.toString() ?? "",
      );
    });
    final options = js.JsObject.jsify({
      "key": keyId,
      "amount": amountPaise,
      "currency": "INR",
      "name": "NaviG8r",
      "description": "Authorize shipment payment",
      "order_id": orderId,
      // Seconds. Razorpay closes checkout after this: 25 minutes, inside the 30 the shipper is told to pay in.
      "timeout": 25 * 60,
      "handler": handler,
      "modal": {
        "ondismiss": js.allowInterop(() => onError("Payment cancelled.")),
      },
    });
    final rzp = js.JsObject(RazorpayCtor, [options]);
    rzp.callMethod("open");
  }
}
