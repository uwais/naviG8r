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

    test('Chandigarh and Delhi are the town when no other part names a town', () {
      expect(townOfAddress('Sector 17, Chandigarh, 160017, India'), 'Chandigarh');
      expect(townOfAddress('Rohini, Delhi, India'), 'Delhi');
      expect(townOfAddress('Connaught Place, New Delhi, Delhi 110001, India'),
          'New Delhi',
          reason: 'a part before it that names it is the town');
      expect(townOfAddress('Leh, Ladakh 194101, India'), 'Leh',
          reason: 'a territory that is not a city is dropped like a state');
    });

    test('Karaikal, Mahe and Yanam before Puducherry stay the town', () {
      expect(townOfAddress('Karaikal, Puducherry 609602, India'), 'Karaikal');
      expect(townOfAddress('Beach Road, Mahe, Puducherry 673310, India'), 'Mahe');
      expect(townOfAddress('Yanam, Puducherry 533464, India'), 'Yanam');
      expect(townOfAddress('Lawspet, Puducherry 605008, India'), 'Puducherry',
          reason: 'an area of the city itself keeps the city as the town');
    });

    test('a leading plus code is not part of the town', () {
      expect(townOfAddress('J8V2+QW Hoskote, Karnataka, India'), 'Hoskote');
    });

    test('a "near ..." landmark is not the town', () {
      expect(townOfAddress('Bengaluru, near Silk Board'), 'Bengaluru');
    });

    test('a one-part address comes back as it is', () {
      expect(townOfAddress('Hosur'), 'Hosur');
      expect(townOfAddress('Delhi'), 'Delhi');
      expect(townOfAddress(''), '');
    });
  });
}
