import 'package:flutter/material.dart';
import 'package:kumbh_tent/core/constants/constants.dart';

/// One bathing day of Simhastha Kumbh Nashik 2027.
///
/// The three Amrit (Shahi) Snans are the peak days — they drive
/// both crowd size and tent surge pricing, so `isAmrit` is what the
/// UI keys its emphasis off, not the star rating.
class SnanEvent {
  const SnanEvent({
    required this.date,
    required this.name,
    required this.significance,
    required this.location,
    this.isAmrit = false,
    this.surge,
  });

  final DateTime date;
  final String name;
  final String significance;
  final String location;
  final bool isAmrit;

  /// Price multiplier shown on the browse banner, e.g. '2x'.
  /// Null for ordinary Parva Snans that carry no surge.
  final String? surge;

  Color get color => isAmrit ? kTrueSaffronDark : kTrueSaffron;
}

/// Master schedule: 17 July – 15 September 2027.
///
/// Dates are the ones consistently reported for the Nashik–
/// Trimbakeshwar Simhastha. Some secondary Parva Snans are still
/// listed as provisional by published calendars, so treat anything
/// that is not an Amrit Snan as subject to change.
final List<SnanEvent> kSnanEvents = [
  SnanEvent(
    date: DateTime.utc(2027, 7, 17),
    name: 'Karka Sankranti',
    significance: 'Opening of the main bathing period',
    location: 'Nashik',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 7, 18),
    name: 'Guru Purnima',
    significance: 'Important religious bathing day',
    location: 'Nashik / Trimbakeshwar',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 7, 29),
    name: 'Nagar Pradakshina',
    significance: 'Major Kumbh procession through the city',
    location: 'Nashik',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 8, 2),
    name: '1st Amrit Snan — Ashadh Amavasya',
    significance:
        'First royal bathing ceremony. The Akhadas conduct their '
        'processions; both Ramkund and Kushavarta Kund are central.',
    location: 'Nashik + Trimbakeshwar',
    isAmrit: true,
    surge: '2x',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 8, 6),
    name: 'Nag Panchami',
    significance: 'Auspicious Snan',
    location: 'Trimbakeshwar / Nashik',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 8, 12),
    name: 'Shravan Putrada Ekadashi',
    significance: 'Auspicious Snan',
    location: 'Nashik / Trimbak',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 8, 17),
    name: 'Shravan Purnima / Raksha Bandhan',
    significance: 'Important Purnima Snan',
    location: 'Nashik / Trimbak',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 8, 31),
    name: '2nd Amrit Snan — Shravan Amavasya',
    significance:
        'The main peak royal bathing day. Expect the largest crowds '
        'of the entire 2027 season.',
    location: 'Nashik + Trimbakeshwar',
    isAmrit: true,
    surge: '2.5x',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 9, 5),
    name: 'Rishi Panchami',
    significance: 'Important Parva Snan',
    location: 'Nashik + Trimbak',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 9, 11),
    name: '3rd Amrit Snan — Vaishnava',
    significance:
        'Bhadrapada Shuddha Ekadashi, associated with the Vaishnava '
        'Akhadas. Main focus is Ramkund.',
    location: 'Nashik / Ramkund',
    isAmrit: true,
    surge: '3x',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 9, 12),
    name: '3rd Amrit Snan — Shaiva',
    significance:
        'Bhadrapada Shuddha Dwadashi, associated with the Shaiva '
        'Akhadas. Main focus is Kushavarta Kund.',
    location: 'Trimbakeshwar / Kushavarta',
    isAmrit: true,
    surge: '3x',
  ),
  SnanEvent(
    date: DateTime.utc(2027, 9, 15),
    name: 'Bhadrapada Purnima',
    significance: 'Closing Purnima Snan',
    location: 'Nashik + Trimbak',
  ),
];

/// Calendar bounds — one month of padding either side so the user
/// can page around the season without hitting a wall immediately.
final DateTime kSnanFirstDay = DateTime.utc(2027, 6, 1);
final DateTime kSnanLastDay = DateTime.utc(2027, 10, 31);

/// Day the calendar opens on: the next upcoming Snan, or the first
/// one if the season has passed. Opening on `DateTime.now()` would
/// land the user on an empty month in 2026.
DateTime get kSnanFocusedDay {
  final now = DateTime.now().toUtc();
  return kSnanEvents
      .firstWhere(
        (e) => !e.date.isBefore(DateTime.utc(now.year, now.month, now.day)),
        orElse: () => kSnanEvents.first,
      )
      .date;
}

/// Events on a given day. TableCalendar hands back local midnights,
/// so compare y/m/d rather than the DateTime itself.
List<SnanEvent> snanEventsOn(DateTime day) => kSnanEvents
    .where(
      (e) =>
          e.date.year == day.year &&
          e.date.month == day.month &&
          e.date.day == day.day,
    )
    .toList();

/// Snans still ahead of today, soonest first.
List<SnanEvent> get kUpcomingSnans {
  final today = DateTime.now();
  final midnight = DateTime.utc(today.year, today.month, today.day);
  return kSnanEvents.where((e) => !e.date.isBefore(midnight)).toList();
}

const List<String> _months = [
  '',
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _weekdays = [
  '',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String snanShortDate(DateTime d) => '${_months[d.month]} ${d.day}';
String snanLongDate(DateTime d) =>
    '${_weekdays[d.weekday]}, ${d.day} ${_months[d.month]} ${d.year}';

/// Whole days from today until [d]; negative once it has passed.
int snanDaysUntil(DateTime d) {
  final now = DateTime.now();
  return d.difference(DateTime.utc(now.year, now.month, now.day)).inDays;
}
