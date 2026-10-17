/// Text the team still has to supply (spec/decisions.md, "Open items"). Screens show these
/// placeholders as they are until the team answers; replace the text here, nowhere else.
abstract final class PendingCopy {
  /// Who a shipper contacts to change or cancel a booking (brief question 6).
  static const changeOrCancelContact = "[NaviG8r contact]";

  /// When a load needs an e-way bill (brief question 7).
  static const whenEwayBillIsNeeded =
      "[One line from the team on when an e-way bill is needed.]";

  static const truckSizeGuide = "[Size guide from the team]";
}
