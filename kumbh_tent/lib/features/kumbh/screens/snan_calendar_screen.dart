import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/constants/snan_calendar.dart';

/// Month-grid calendar of the 2027 Simhastha Snan schedule.
///
/// Opened from the calendar icon in the browse header. Marked days
/// carry a dot (saffron for Parva Snans, dark saffron for the three
/// Amrit Snans); tapping any day shows what falls on it.
class SnanCalendarScreen extends StatefulWidget {
  const SnanCalendarScreen({super.key});

  @override
  State<SnanCalendarScreen> createState() => _SnanCalendarScreenState();
}

class _SnanCalendarScreenState extends State<SnanCalendarScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  CalendarFormat _format = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _focusedDay = kSnanFocusedDay;
    _selectedDay = _focusedDay;
  }

  @override
  Widget build(BuildContext context) {
    final selected = snanEventsOn(_selectedDay);
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Snan Calendar',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              'Simhastha Kumbh Nashik 2027',
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: ListView(
        children: [
          _calendarCard(),
          _selectedDayPanel(selected),
          _legend(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'All Snan Dates',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kLuxDark,
              ),
            ),
          ),
          ...kSnanEvents.map(_snanTile),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: Text(
              'Amrit Snan dates are confirmed. Some secondary Parva '
              'Snans are still listed as provisional by published '
              'calendars and may shift.',
              style: TextStyle(fontSize: 11, color: kLuxMuted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kTrueSaffron.withOpacity(0.18)),
      ),
      child: TableCalendar<SnanEvent>(
        firstDay: kSnanFirstDay,
        lastDay: kSnanLastDay,
        focusedDay: _focusedDay,
        calendarFormat: _format,
        eventLoader: snanEventsOn,
        startingDayOfWeek: StartingDayOfWeek.monday,
        selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
        onDaySelected: (selected, focused) => setState(() {
          _selectedDay = selected;
          _focusedDay = focused;
        }),
        onFormatChanged: (f) => setState(() => _format = f),
        onPageChanged: (focused) => _focusedDay = focused,
        availableCalendarFormats: const {
          CalendarFormat.month: 'Month',
          CalendarFormat.twoWeeks: '2 weeks',
        },
        headerStyle: HeaderStyle(
          titleCentered: true,
          formatButtonVisible: false,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: kLuxDark,
          ),
          leftChevronIcon: const Icon(Icons.chevron_left, color: kTrueSaffron),
          rightChevronIcon: const Icon(Icons.chevron_right, color: kTrueSaffron),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
          weekendStyle: GoogleFonts.poppins(
            fontSize: 11,
            color: kTrueSaffronDark,
          ),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          todayDecoration: BoxDecoration(
            color: kTrueSaffron.withOpacity(0.22),
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(color: kLuxDark),
          selectedDecoration: const BoxDecoration(
            color: kTrueSaffron,
            shape: BoxShape.circle,
          ),
          defaultTextStyle: GoogleFonts.poppins(fontSize: 13, color: kLuxDark),
          weekendTextStyle: GoogleFonts.poppins(
            fontSize: 13,
            color: kTrueSaffronDark,
          ),
        ),
        calendarBuilders: CalendarBuilders<SnanEvent>(
          // A plain marker dot cannot distinguish an Amrit Snan from
          // an ordinary Parva Snan, and that distinction is the whole
          // point of the calendar — so draw the marker ourselves.
          markerBuilder: (context, day, events) {
            if (events.isEmpty) return null;
            final isAmrit = events.any((e) => e.isAmrit);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              width: isAmrit ? 7 : 5,
              height: isAmrit ? 7 : 5,
              decoration: BoxDecoration(
                color: isAmrit ? kTrueSaffronDark : kTrueSaffron,
                shape: BoxShape.circle,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _selectedDayPanel(List<SnanEvent> events) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: events.isEmpty ? Colors.white : kTrueSaffron.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: events.isEmpty
              ? kLuxBorder
              : kTrueSaffron.withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snanLongDate(_selectedDay),
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kLuxMuted,
            ),
          ),
          const SizedBox(height: 6),
          if (events.isEmpty)
            Text(
              'No Snan on this day.',
              style: GoogleFonts.poppins(fontSize: 13, color: kLuxMuted),
            )
          else
            ...events.map(
              (e) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.name,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: e.color,
                          ),
                        ),
                      ),
                      if (e.surge != null) _surgePill(e.surge!),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    e.significance,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: kLuxDark,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: kLuxMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          e.location,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: kLuxMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _snanTile(SnanEvent e) {
    final days = snanDaysUntil(e.date);
    return GestureDetector(
      onTap: () => setState(() {
        _selectedDay = e.date;
        _focusedDay = e.date;
      }),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: e.isAmrit ? kTrueSaffron.withOpacity(0.45) : kLuxBorder,
            width: e.isAmrit ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: e.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    '${e.date.day}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: e.color,
                    ),
                  ),
                  Text(
                    snanShortDate(e.date).split(' ').first,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: kLuxMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kLuxDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    e.location,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: kLuxMuted,
                    ),
                  ),
                  if (e.isAmrit)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '★ Amrit Snan',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: kTrueSaffronDark,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (days >= 0)
              Text(
                days == 0 ? 'Today' : 'in ${days}d',
                style: GoogleFonts.poppins(fontSize: 10, color: kLuxMuted),
              ),
          ],
        ),
      ),
    );
  }

  Widget _surgePill(String surge) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: kTrueSaffronDark,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$surge pricing',
      style: GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );

  Widget _legend() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        _legendDot(kTrueSaffronDark, 7, 'Amrit / Shahi Snan'),
        const SizedBox(width: 16),
        _legendDot(kTrueSaffron, 5, 'Parva Snan'),
      ],
    ),
  );

  Widget _legendDot(Color c, double size, String label) => Row(
    children: [
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
      ),
    ],
  );
}
