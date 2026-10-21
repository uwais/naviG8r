// One concern: the short place a carrier list shows for a booking's full pickup or drop address.

/// India's states and union territories, as Google writes them at the end of an address.
const _statesAndTerritories = {
  "andhra pradesh", "arunachal pradesh", "assam", "bihar", "chhattisgarh", "goa",
  "gujarat", "haryana", "himachal pradesh", "jharkhand", "karnataka", "kerala",
  "madhya pradesh", "maharashtra", "manipur", "meghalaya", "mizoram", "nagaland",
  "odisha", "punjab", "rajasthan", "sikkim", "tamil nadu", "telangana", "tripura",
  "uttar pradesh", "uttarakhand", "west bengal", "andaman and nicobar islands",
  "chandigarh", "dadra and nagar haveli and daman and diu", "delhi",
  "jammu and kashmir", "ladakh", "lakshadweep", "puducherry",
};

final _pinCode = RegExp(r"\s*\b\d{6}\b\s*");

/// The town of an address, its last part before the state, pin code and country:
/// "Plot 5, Sector 18, Gurugram, Haryana 122015, India" gives "Gurugram", "Peenya, Bengaluru"
/// gives "Bengaluru". A one-part address comes back as it is. Lists show this; the booking
/// screen and the driver's next stop keep the full address.
String townOfAddress(String address) {
  final parts = address
      .split(",")
      .map((part) => part.replaceAll(_pinCode, " ").trim())
      .where((part) => part.isNotEmpty)
      .toList();
  bool notATown(String part) =>
      part.toLowerCase() == "india" ||
      _statesAndTerritories.contains(part.toLowerCase());
  while (parts.length > 1 && notATown(parts.last)) {
    parts.removeLast();
  }
  return parts.isEmpty ? address.trim() : parts.last;
}
