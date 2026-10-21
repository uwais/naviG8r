import 'package:flutter_test/flutter_test.dart';
import 'package:driver_pilot/address_town.dart';

void main() {
  group('townOfAddress, the short place carrier lists show', () {
    test('a typed area and town gives the town', () {
      expect(townOfAddress('Peenya, Bengaluru'), 'Bengaluru');
      expect(townOfAddress('Plot 12, 4th Cross, Bommasandra, Bengaluru'),
          'Bengaluru');
    });

    test("Google's full address drops the state, pin code and country", () {
      expect(
          townOfAddress('Plot 5, Sector 18, Gurugram, Haryana 122015, India'),
          'Gurugram');
      expect(townOfAddress('Guindy, Chennai, Tamil Nadu, India'), 'Chennai');
      expect(townOfAddress('Koramangala, Bengaluru 560034'), 'Bengaluru');
    });

    test('a one-part address comes back as it is', () {
      expect(townOfAddress('Hosur'), 'Hosur');
      expect(townOfAddress('Delhi'), 'Delhi');
      expect(townOfAddress(''), '');
    });
  });
}
