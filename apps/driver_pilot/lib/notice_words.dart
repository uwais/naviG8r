/// Plain words for a notice, by what happened and to whom, or null for an event the app does not
/// know. The server's own titles say "load" and "organization", so the app words them itself.
String? noticeWords(String eventKey, {required bool forShipper}) {
  if (forShipper) {
    return switch (eventKey) {
      'shipment.booked' => 'Your shipment is booked.',
      'shipment.carrier_accepted' => 'The carrier accepted your shipment.',
      'trip.started' => 'Your goods are on the way.',
      'trip.completed' => 'The trip is complete.',
      'shipment.pod_submitted' => 'The carrier confirmed delivery.',
      'shipment.pod_accepted' => 'Delivery accepted.',
      'payment.status_changed' => 'Your payment was updated.',
      'conversation.message' => 'New message on a shipment.',
      _ => null,
    };
  }
  return switch (eventKey) {
    'shipment.booked' => 'New booking from a shipper.',
    'shipment.carrier_accepted' => 'Booking accepted.',
    'trip.started' => 'Trip started.',
    'trip.completed' => 'Trip complete.',
    'shipment.pod_submitted' => 'Delivery confirmed.',
    'shipment.pod_accepted' => 'The shipper accepted the delivery.',
    'payment.status_changed' => 'A payment was updated.',
    'conversation.message' => 'New message on a booking.',
    _ => null,
  };
}
