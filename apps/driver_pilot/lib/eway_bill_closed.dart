/// True once a shipment is delivered, refunded or its delivery accepted. The server refuses every change
/// to the e-way bill from then on, so neither card offers one.
bool ewayBillIsClosed(Map<String, dynamic> shipment) =>
    shipment['status'] == 'DELIVERED' ||
    shipment['status'] == 'FAILED_CARRIER_REFUNDED' ||
    shipment['podAcceptedAtUtcMs'] != null;
