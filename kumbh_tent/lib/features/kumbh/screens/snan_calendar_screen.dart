import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:kumbh_tent/core/constants/snan_calendar.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/shared/widgets/premium_badge.dart';

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
    final upcoming = kUpcomingSnans;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _header(),
            if (upcoming.isNotEmpty) _countdownCard(upcoming.first),
            _calendarCard(),
            _selectedDayPanel(selected),
            _legend(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.saffron.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      size: 16,
                      color: AppColors.saffron,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'All Snan Dates',
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            ...kSnanEvents.map(_snanTile),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'Amrit Snan dates are confirmed. Some secondary Parva '
                'Snans are still listed as provisional by published '
                'calendars and may shift.',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 20, 4),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Snan Calendar',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                'Simhastha Kumbh Nashik 2027',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _countdownCard(SnanEvent next) {
    final days = snanDaysUntil(next.date);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.saffron, AppColors.saffronDark],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.saffron.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.water_drop_rounded,
                            color: Colors.white70,
                            size: 12,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'NEXT SNAN',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        next.name,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        snanLongDate(next.date),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                      if (next.isAmrit) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '★ Amrit Snan',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$days',
                        style: GoogleFonts.poppins(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'days',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
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
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          leftChevronIcon: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.softSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.chevron_left_rounded,
              color: AppColors.saffron,
              size: 20,
            ),
          ),
          rightChevronIcon: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.softSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.saffron,
              size: 20,
            ),
          ),
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle: GoogleFonts.poppins(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
          weekendStyle: GoogleFonts.poppins(
            fontSize: 11,
            color: AppColors.saffronDark,
          ),
        ),
        calendarStyle: CalendarStyle(
          outsideDaysVisible: false,
          todayDecoration: BoxDecoration(
            color: AppColors.saffron.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.saffron.withValues(alpha: 0.5),
            ),
          ),
          todayTextStyle: const TextStyle(
            color: AppColors.saffronDark,
            fontWeight: FontWeight.w600,
          ),
          selectedDecoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.saffron, AppColors.saffronDark],
            ),
            shape: BoxShape.circle,
          ),
          defaultTextStyle: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
          weekendTextStyle: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.saffronDark,
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
                gradient: isAmrit
                    ? const LinearGradient(
                        colors: [AppColors.saffron, AppColors.goldWarm],
                      )
                    : null,
                color: isAmrit ? null : AppColors.saffron,
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
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: events.isEmpty
            ? AppColors.softSurface
            : AppColors.goldWarm.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: events.isEmpty
              ? AppColors.border
              : AppColors.goldWarm.withValues(alpha: 0.3),
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
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            Text(
              'No Snan on this day.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: e.color,
                          ),
                        ),
                      ),
                      if (e.surge != null)
                        PremiumBadge(
                          label: '${e.surge} pricing',
                          style: PremiumBadgeStyle.saffron,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    e.significance,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          e.location,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textMuted,
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
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: e.isAmrit
                ? AppColors.goldWarm.withValues(alpha: 0.5)
                : AppColors.cardBorder,
            width: e.isAmrit ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: e.isAmrit ? 0.08 : 0.05,
              ),
              blurRadius: e.isAmrit ? 16 : 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: e.isAmrit
                    ? LinearGradient(
                        colors: [
                          e.color.withValues(alpha: 0.9),
                          AppColors.goldWarm,
                        ],
                      )
                    : null,
                color: e.isAmrit ? null : e.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${e.date.day}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: e.isAmrit ? Colors.white : e.color,
                    ),
                  ),
                  Text(
                    snanShortDate(e.date).split(' ').first,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: e.isAmrit
                          ? Colors.white70
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    e.location,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (e.isAmrit)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: PremiumBadge(
                        label: 'AMRIT SNAN',
                        style: PremiumBadgeStyle.gold,
                        icon: Icons.star_rounded,
                      ),
                    ),
                ],
              ),
            ),
            if (days >= 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.softSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  days == 0 ? 'Today' : 'in ${days}d',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _legend() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Row(
      children: [
        _legendDot(AppColors.goldWarm, 'Amrit / Shahi Snan'),
        const SizedBox(width: 20),
        _legendDot(AppColors.saffron, 'Parva Snan'),
      ],
    ),
  );

  Widget _legendDot(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textMuted),
      ),
    ],
  );
}
