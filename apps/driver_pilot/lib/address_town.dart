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

/// Territories that are also cities. Google writes the name once when the city is the territory
/// ("Sector 17, Chandigarh, 160017, India"), so there it is the town; a part before it that
/// names it is the town instead ("New Delhi, Delhi").
const _territoriesThatAreCities = {"chandigarh", "delhi", "puducherry"};

/// Puducherry's towns away from the city: "Karaikal, Puducherry 609602, India" is in Karaikal.
const _puducherryTowns = {"karaikal", "mahe", "mahé", "yanam"};

final _pinCode = RegExp(r"\s*\b\d{6}\b\s*");

/// A Google plus code at the start of a part: "J8V2+QW Hoskote".
final _leadingPlusCode =
    RegExp(r"^[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}\s*", caseSensitive: false);

/// The town of an address, its last part before the state, pin code and country:
/// "Plot 5, Sector 18, Gurugram, Haryana 122015, India" gives "Gurugram", "Peenya, Bengaluru"
/// gives "Bengaluru". A trailing "near ..." landmark is not the town. A one-part address comes
/// back as it is. Lists show this; the booking screen and the driver's next stop keep the full
/// address.
String townOfAddress(String address) {
  final parts = address
      .split(",")
      .map((part) =>
          part.replaceAll(_pinCode, " ").replaceFirst(_leadingPlusCode, "").trim())
      .where((part) => part.isNotEmpty)
      .toList();
  bool notATown(String part) {
    final name = part.toLowerCase();
    if (name == "india" || name.startsWith("near ")) return true;
    if (!_statesAndTerritories.contains(name)) return false;
    if (!_territoriesThatAreCities.contains(name)) return true;
    final before = parts.length > 1 ? parts[parts.length - 2].toLowerCase() : "";
    return before.contains(name) || (name == "puducherry" && _puducherryTowns.contains(before));
  }

  while (parts.length > 1 && notATown(parts.last)) {
    parts.removeLast();
  }
  return parts.isEmpty ? address.trim() : parts.last;
}
