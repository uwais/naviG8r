import 'package:driver_pilot/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 17, 6);

  group('Date', () {
    test('this year reads "18 Oct", with no year and no numbers-only form', () {
      expect(formatDate(DateTime.utc(2026, 10, 18, 6), now: now), '18 Oct',
          reason:
              'copy.md Formats: a date is "18 Oct", never 2026-10-18 or 10/18');
    });

    test('another year adds the year', () {
      expect(formatDate(DateTime.utc(2027, 1, 2, 6), now: now), '2 Jan 2027',
          reason:
              'copy.md Formats: "18 Oct 2026" when the year is not this year');
    });

    test('a form shows the year even this year', () {
      expect(
          formatDate(DateTime.utc(2026, 10, 18, 6), now: now, withYear: true),
          '18 Oct 2026',
          reason: 'copy.md Formats: the year is shown in a form');
    });

    test('the day is the day in India, not on the phone', () {
      // 20:00 UTC on 17 Oct is 01:30 on 18 Oct in India.
      expect(formatDate(DateTime.utc(2026, 10, 17, 20), now: now), '18 Oct',
          reason: 'dates are read in India time whatever zone the phone is in');
    });

    test('a range in one month reads "18 – 19 Oct"', () {
      expect(
          formatDateRange(
              DateTime.utc(2026, 10, 18, 6), DateTime.utc(2026, 10, 19, 6),
              now: now),
          '18 – 19 Oct',
          reason: 'copy.md Formats: a range is "18 – 19 Oct"');
    });

    test('a range across months names both months', () {
      expect(
          formatDateRange(
              DateTime.utc(2026, 10, 30, 6), DateTime.utc(2026, 11, 2, 6),
              now: now),
          '30 Oct – 2 Nov',
          reason: 'a range across months must say which month each end is in');
    });

    test('a range on one day is just that day', () {
      expect(
          formatDateRange(
              DateTime.utc(2026, 10, 18, 4), DateTime.utc(2026, 10, 18, 12),
              now: now),
          '18 Oct',
          reason: 'a one-day range must not read "18 – 18 Oct"');
    });

    test('a range across years names both years', () {
      expect(
          formatDateRange(
              DateTime.utc(2026, 12, 30, 6), DateTime.utc(2027, 1, 2, 6),
              now: now),
          '30 Dec 2026 – 2 Jan 2027',
          reason: 'copy.md Formats: the year appears when it is not this year');
    });
  });

  group('Time', () {
    test('is India time, 24-hour, ending in IST', () {
      // 11:10 UTC is 16:40 in India.
      expect(formatTimeIst(DateTime.utc(2026, 10, 18, 11, 10)), '16:40 IST',
          reason:
              'copy.md Formats: time is "16:40 IST" (24-hour), never "4:40 PM"');
    });

    test('pads early hours and minutes', () {
      // 20:35 UTC is 02:05 the next day in India.
      expect(formatTimeIst(DateTime.utc(2026, 10, 17, 20, 35)), '02:05 IST',
          reason: 'a 24-hour time always has two digits for the hour');
    });
  });

  group('Money', () {
    test('uses Indian grouping', () {
      expect(formatRupees(264000), '₹2,640',
          reason: 'copy.md Formats: money is "₹2,640"');
      expect(formatRupees(12500000), '₹1,25,000',
          reason: 'Indian grouping: lakhs are "1,25,000", not "125,000"');
      expect(formatRupees(1234567800), '₹1,23,45,678',
          reason: 'Indian grouping keeps pairs above the thousands');
      expect(formatRupees(99900), '₹999', reason: 'three digits need no comma');
    });

    test('shows no paise unless there are some', () {
      expect(formatRupees(470400), '₹4,704',
          reason: 'copy.md Formats: no paise unless paise matter');
      expect(formatRupees(470435), '₹4,704.35',
          reason: 'non-zero paise must not be hidden from the amount charged');
      expect(formatRupees(470405), '₹4,704.05',
          reason: 'paise always have two digits');
    });
  });

  group('Weight', () {
    test('reads "80 kg"', () {
      expect(formatKg(80), '80 kg',
          reason: 'copy.md Formats: weight is "80 kg"');
      expect(formatKg(80.0), '80 kg',
          reason: 'a whole weight never shows ".0"');
      expect(formatKg(80.5), '80.5 kg',
          reason: 'a part kilogram is not rounded away');
    });
  });

  group('IDs', () {
    test('a bill number is shown in groups of four', () {
      expect(formatBillNumber('341200987654'), '3412 0098 7654',
          reason: 'copy.md Formats: bill numbers shown as 3412 0098 7654');
      expect(formatBillNumber('3412 0098 7654'), '3412 0098 7654',
          reason: 'an already spaced number is regrouped, not doubled up');
    });

    test('a shipment is named by its route and date, never by ID', () {
      expect(
          shipmentName(
              from: 'Bengaluru',
              to: 'Chennai',
              date: DateTime.utc(2026, 10, 18, 6),
              now: now),
          'Bengaluru to Chennai, 18 Oct',
          reason: 'copy.md Formats: route plus date, never SHP_4135');
    });
  });

  group('Phone', () {
    test('a mobile number reads "+91 98450 12345"', () {
      expect(formatPhone('9845012345'), '+91 98450 12345',
          reason:
              'copy.md: the account menu and code screen show the full phone');
      expect(formatPhone('+91 98450-12345'), '+91 98450 12345',
          reason: 'a number already carrying 91 is not given it twice');
    });

    test('anything that is not a mobile number is left as it was', () {
      expect(formatPhone('12345'), '12345',
          reason: 'a number we cannot read is shown, not guessed at');
    });
  });
}
