import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/payment/screens/payment_screen.dart';
import 'package:kumbh_tent/features/booking/screens/coupons_screen.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

class BookingFormScreen extends StatefulWidget {
  final Map<String, dynamic> tent;
  const BookingFormScreen({super.key, required this.tent});

  @override
  State<BookingFormScreen> createState() => _BookingFormScreenState();
}

class _BookingFormScreenState extends State<BookingFormScreen> {
  DateTime? _checkIn;
  DateTime? _checkOut;
  int _guests = 1;
  int _units = 1;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _idProofController = TextEditingController();
  final _couponController = TextEditingController();

  bool _couponApplied = false;
  String _appliedCouponCode = '';
  double _couponDiscountRate = 0.0;
  bool _isBooking = false;

  String _genderPreference = 'Other';
  String _bedType = 'Single';
  final String _idType = 'Aadhaar';

  String? _nameError;
  String? _phoneError;
  String? _idProofError;

  // Airport/station pickup, puja kit, and Pilgrim Services
  // (Godavari walk, prasad thali) add-ons were removed from the
  // booking form. Their state, charges, price rows and booking
  // payload keys went with them so no hidden ₹0 line items or
  // dead flags remain.

  // Children traveling with the group. Under-5s stay free (capped
  // per tent, same as most hotel policies); 5-12s are old enough
  // to need their own bedding/meals so a per-night child fee
  // applies — there's no bunk-bed-for-a-toddler option here.
  bool _hasChildren = false;
  int _childrenUnder5 = 0;
  int _childrenAbove5 = 0;
  static const double _childFeePerNight = 500.0;

  // ── Per-date availability (for calendar color coding) ───────
  //
  // date-string ('YYYY-MM-DD') -> remaining units that day. Loaded
  // once for the whole bookable window so every visible month is
  // colored without a fetch per page-swipe; refreshed after a
  // successful booking so colors reflect the new state immediately.
  final Map<String, int> _remainingByDate = {};
  int _tentTotalUnits = 0;
  bool _availabilityLoading = true;

  final DateTime _calendarFirstDay = DateTime.now();
  final DateTime _calendarLastDay = DateTime(2027, 10, 31);

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
    _loadAvailability();
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadAvailability() async {
    setState(() => _availabilityLoading = true);
    try {
      final data = await ApiService.getTentAvailability(
        tentId: widget.tent['id'].toString(),
        start: _dateKey(_calendarFirstDay),
        // end is exclusive, so pass the day after the last bookable day.
        end: _dateKey(_calendarLastDay.add(const Duration(days: 1))),
      );
      final days = data['days'] as List<dynamic>? ?? [];
      if (!mounted) return;
      setState(() {
        _tentTotalUnits = (data['total_units'] as num?)?.toInt() ??
            (widget.tent['total_units'] as num?)?.toInt() ??
            0;
        _remainingByDate.clear();
        for (final d in days) {
          _remainingByDate[d['date'] as String] =
              (d['remaining_units'] as num).toInt();
        }
      });
    } catch (_) {
      // Availability is a UI hint (color coding), not the source of
      // truth — createBooking re-validates for real. If this fetch
      // fails, fall back to letting every future date look normal
      // rather than blocking the calendar entirely.
    } finally {
      if (mounted) setState(() => _availabilityLoading = false);
    }
  }

  /// Remaining units for [day], or the tent's total if we have no
  /// data for it yet (e.g. still loading, or outside the fetched
  /// window) — fails open visually rather than showing every date
  /// as sold out before the network call lands.
  int _remainingFor(DateTime day) =>
      _remainingByDate[_dateKey(day)] ?? _tentTotalUnits;

  bool _isDaySelectable(DateTime day) {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    if (day.isBefore(todayMidnight)) return false;
    if (_tentTotalUnits > 0 && _remainingFor(day) <= 0) return false;

    // A start date is already picked and we're choosing the end —
    // every date the range would span must still have at least 1
    // unit free, or this can't be a valid end date.
    if (_checkIn != null && _checkOut == null && day.isAfter(_checkIn!)) {
      for (DateTime d = _checkIn!;
          !d.isAfter(day);
          d = d.add(const Duration(days: 1))) {
        if (_tentTotalUnits > 0 && _remainingFor(d) <= 0) return false;
      }
    }
    return true;
  }

  Widget _availabilityLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted),
        ),
      ],
    );
  }

  /// Colors a day cell green/amber/red by remaining-units percentage.
  /// Returns null (falls back to table_calendar's own default look)
  /// once availability hasn't loaded yet, so dates don't flash red
  /// before the fetch lands.
  Widget? _buildAvailabilityCell(DateTime day) {
    if (_tentTotalUnits <= 0) return null;
    final remaining = _remainingFor(day);
    final isPast = day.isBefore(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    if (isPast) return null;

    Color bg;
    Color textColor;
    bool strikeThrough = false;
    bool isNormal = false;
    if (remaining <= 0) {
      bg = AppColors.error.withValues(alpha: 0.12);
      textColor = AppColors.error;
      strikeThrough = true;
    } else if (remaining <= (_tentTotalUnits * 0.2).ceil()) {
      bg = AppColors.warning.withValues(alpha: 0.20);
      textColor = AppColors.saffronDark;
    } else {
      // > 20% remaining — green, same as every other available day.
      // Drawn explicitly (not left to fall back to table_calendar's
      // own default look) so Saturday/Sunday get identical treatment
      // to weekdays — the library's built-in weekendTextStyle grays
      // weekends out on its own, which made an available Sat/Sun
      // look booked even though it wasn't.
      bg = AppColors.success.withValues(alpha: 0.12);
      textColor = AppColors.success;
      isNormal = true;
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.day}',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w600,
              decoration: strikeThrough ? TextDecoration.lineThrough : null,
            ),
          ),
          if (!strikeThrough && !isNormal)
            Text(
              '$remaining left',
              style: GoogleFonts.poppins(fontSize: 7, color: textColor),
            ),
        ],
      ),
    );
  }

  Future<void> _loadUserDetails() async {
    final name = await ApiService.getStoredName();
    final phone = await ApiService.getStoredPhone();
    final gender = await ApiService.getGenderPreference();
    if (mounted) {
      setState(() {
        if (name != null && name.isNotEmpty) _nameController.text = name;
        if (phone != null && phone.isNotEmpty) _phoneController.text = phone;
        _genderPreference = gender;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _idProofController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  int get _nights => (_checkIn == null || _checkOut == null)
      ? 0
      : _checkOut!.difference(_checkIn!).inDays;
  double get _baseTotal => widget.tent['price'] * _nights * _units.toDouble();
  // A Double bed is a bigger tent footprint than a Single, so it
  // costs more — same idea as Airbnb charging more for a bigger
  // room. Only shown/added when it actually applies (Double
  // selected); a Single booking's total is unaffected.
  static const double _doubleBedSurchargeRate = 0.20;
  double get _bedTypeSurcharge => _bedType == 'Double'
      ? _baseTotal * _doubleBedSurchargeRate
      : 0;
  double get _childrenCharge =>
      _hasChildren ? _childrenAbove5 * _childFeePerNight * _nights : 0;
  double get _addonsTotal => _bedTypeSurcharge + _childrenCharge;

  // Both children brackets are capped at 2 per booking (matches
  // common hotel/camp policy for a shared bed) regardless of units;
  // total children can also never exceed the guest count they're
  // counted within.
  static const int _maxChildrenUnder5 = 2;
  static const int _maxChildrenAbove5 = 2;
  int get _maxTotalChildren => _guests;
  double get _subtotal => _baseTotal + _addonsTotal;
  double get _discount => _couponApplied ? _subtotal * _couponDiscountRate : 0;
  double get _taxableAmount => _subtotal - _discount;
  // BUG-03/04: GST slab is set by the nightly tariff, not the
  // taxable stay total — matches pricing.go server-side.
  double get _gstRate => gstRateFor((widget.tent['price'] as num).toDouble());
  double get _tax => _taxableAmount * _gstRate;
  double get _cgst => _tax / 2;
  double get _sgst => _tax / 2;
  double get _grandTotal => _subtotal - _discount + _tax;

  // ── Capacity limits ─────────────────────────────────────────
  //
  // Same rule as Airbnb: the bed you pick is the number of people
  // it sleeps, no more. A Single bed sleeps 1 guest per tent, a
  // Double sleeps 2 — not "up to" some larger shared-room number.
  // Units are additionally capped by how many tents the listing
  // actually has available.
  int get _guestsPerUnit => _bedType == 'Single' ? 1 : 2;
  int get _maxGuests => _guestsPerUnit * _units;
  int get _maxUnits {
    final available = widget.tent['available'];
    if (available is int && available > 0) return available;
    return 10;
  }

  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    try {
      final res = await ApiService.validateCoupon(
        code: code,
        amount: _subtotal,
      );
      if (res['valid'] == true) {
        setState(() {
          _couponApplied = true;
          _appliedCouponCode = code;
          _couponDiscountRate = (res['discount'] as num).toDouble();
        });
        _snack(res['message'] ?? 'Coupon applied!', AppColors.success);
      } else {
        setState(() {
          _couponApplied = false;
          _appliedCouponCode = '';
          _couponDiscountRate = 0;
        });
        _snack(res['message'] ?? 'Invalid coupon', AppColors.error);
      }
    } catch (_) {
      _snack('Could not validate coupon', AppColors.error);
    }
  }

  /// Validates the guest-detail fields and sets inline error text
  /// on each one that's wrong, instead of only a generic snackbar
  /// that gives no indication of *which* field to fix.
  bool _validateGuestDetails() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    final idProofText = _idProofController.text.trim();
    final idProofDigits = idProofText.replaceAll(RegExp(r'\D'), '');

    setState(() {
      _nameError = name.isEmpty ? 'Please enter guest name' : null;
      _phoneError = phoneDigits.length != 10
          ? 'Enter a valid 10-digit phone number'
          : null;
      _idProofError = _idType == 'Aadhaar'
          ? (idProofDigits.length != 12
                ? 'Enter a valid 12-digit Aadhaar number'
                : null)
          : (idProofText.length < 6
                ? 'Enter a valid passport number'
                : null);
    });

    return _nameError == null && _phoneError == null && _idProofError == null;
  }

  Future<void> _proceedToPayment() async {
    if (!_validateGuestDetails()) {
      _snack('Please fix the highlighted fields', AppColors.error);
      return;
    }
    if (_checkIn == null || _checkOut == null) {
      _snack('Please select dates', AppColors.error);
      return;
    }
    setState(() => _isBooking = true);
    try {
      final result = await ApiService.createBooking(
        tentId: widget.tent['id'].toString(),
        checkIn: _checkIn!.toIso8601String().substring(0, 10),
        checkOut: _checkOut!.toIso8601String().substring(0, 10),
        guests: _guests,
        units: _units,
        couponCode: _couponApplied ? _appliedCouponCode : null,
        addons: {
          'guest_name': _nameController.text.trim(),
          'guest_phone': _phoneController.text.trim(),
          'id_proof': _idProofController.text.trim(),
          'id_type': _idType,
          'bed_type': _bedType,
          'gender_preference': _genderPreference,
          'has_children': _hasChildren,
          'children_under_5': _childrenUnder5,
          'children_5_to_12': _childrenAbove5,
        },
      );
      final serverBooking = result['booking'] as Map<String, dynamic>;
      final bookingRef = serverBooking['booking_ref'] as String;
      final serverBase = (serverBooking['base_amount'] as num).toDouble();
      final serverDiscount = (serverBooking['discount'] as num).toDouble();
      final serverTax = (serverBooking['tax'] as num).toDouble();
      // Units just booked are no longer free — refresh so the
      // calendar's colors reflect the new state immediately.
      unawaited(_loadAvailability());
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentScreen(
              tent: widget.tent,
              checkIn: _checkIn!,
              checkOut: _checkOut!,
              guests: _guests,
              units: _units,
              totalAmount: _grandTotal,
              taxableAmount: serverBase - serverDiscount,
              tax: serverTax,
              bookingRef: bookingRef,
              couponCode: _couponApplied ? _appliedCouponCode : null,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Failed to create booking. Please try again.';
        if (e.toString().contains('409') ||
            e.toString().contains('not available')) {
          msg = '🚫 Tent already booked for selected dates.';
          // Our cached colors were stale — someone else took those
          // units between page-load and submit. Refresh so the
          // calendar reflects reality before the user tries again.
          unawaited(_loadAvailability());
        } else if (e.toString().contains('400')) {
          msg = 'Invalid booking details.';
        } else if (e.toString().contains('401')) {
          msg = 'Session expired. Please login again.';
        }
        _snack(msg, AppColors.error);
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
    }
  }

  /// Keeps the children counts valid after guests/tents shrink —
  /// otherwise a guest count drop could leave more "children"
  /// recorded than total guests, or more free under-5s than the
  /// per-tent allowance covers.
  void _clampChildren() {
    if (_childrenUnder5 > _maxChildrenUnder5) {
      _childrenUnder5 = _maxChildrenUnder5;
    }
    if (_childrenAbove5 > _maxChildrenAbove5) {
      _childrenAbove5 = _maxChildrenAbove5;
    }
    if (_childrenUnder5 + _childrenAbove5 > _maxTotalChildren) {
      _childrenAbove5 = (_maxTotalChildren - _childrenUnder5).clamp(
        0,
        _maxTotalChildren,
      );
    }
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tentImages = widget.tent['images'] as List<String>? ?? [];
    return Scaffold(
      backgroundColor: AppColors.background,

      // ── AppBar — white, matches new theme ──────────────────
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              'Book Your Tent',
              style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            Text(
              'KUMBH MELA · NASHIK 2027',
              style: GoogleFonts.poppins(
                color: AppColors.textMuted,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Tent card ────────────────────────────────────
            _card(
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: buildTentImage(
                        tentImages.isNotEmpty ? tentImages.first : '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.tent['name'],
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          widget.tent['location'],
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${widget.tent['price']} / night',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.saffronDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 2. Guest details ────────────────────────────────
            _smallLabel('GUEST DETAILS'),
            const SizedBox(height: 12),
            _card(
              child: Column(
                children: [
                  _field(
                    'Full name',
                    'Kumbh User',
                    _nameController,
                    TextInputType.name,
                    errorText: _nameError,
                    onChanged: (_) {
                      if (_nameError != null) {
                        setState(() => _nameError = null);
                      }
                    },
                  ),
                  _divider(),
                  _field(
                    'Mobile number',
                    '+91 9876543210',
                    _phoneController,
                    TextInputType.phone,
                    errorText: _phoneError,
                    // Digits only, capped at 10 — stops the field itself
                    // from ever holding an 11+ digit number (typed or
                    // pasted) instead of only catching it on submit.
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: (_) {
                      if (_phoneError != null) {
                        setState(() => _phoneError = null);
                      }
                    },
                  ),
                  _divider(),
                  Text(
                    'ID proof type',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.saffron, AppColors.saffronDark],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Aadhaar',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    'Aadhaar number',
                    '•••• •••• ••••',
                    _idProofController,
                    TextInputType.number,
                    errorText: _idProofError,
                    inputFormatters: [_AadhaarNumberFormatter()],
                    onChanged: (_) {
                      if (_idProofError != null) {
                        setState(() => _idProofError = null);
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 3. Select dates ─────────────────────────────────
            _smallLabel('SELECT DATES'),
            const SizedBox(height: 12),
            _card(
              child: Column(
                children: [
                  // Date pills
                  Row(
                    children: [
                      Expanded(child: _datePill('CHECK-IN', _checkIn)),
                      const SizedBox(width: 10),
                      Expanded(child: _datePill('CHECK-OUT', _checkOut)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_availabilityLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  // Legend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _availabilityLegendDot(AppColors.success, 'Available'),
                      const SizedBox(width: 14),
                      _availabilityLegendDot(AppColors.warning, 'Few left'),
                      const SizedBox(width: 14),
                      _availabilityLegendDot(AppColors.error, 'Sold out'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Calendar
                  TableCalendar(
                    firstDay: DateTime.now(),
                    lastDay: DateTime(2027, 10, 31),
                    focusedDay: _checkIn ?? DateTime(2027, 8, 1),
                    rangeStartDay: _checkIn,
                    rangeEndDay: _checkOut,
                    rangeSelectionMode: RangeSelectionMode.toggledOn,
                    // Horizontal only — table_calendar's default (`all`)
                    // also claims vertical drags to toggle month/week
                    // format, which steals the gesture from the page's
                    // own scroll before it ever reaches the outer
                    // SingleChildScrollView. That's what made the whole
                    // screen feel unscrollable near the calendar.
                    availableGestures: AvailableGestures.horizontalSwipe,
                    enabledDayPredicate: _isDaySelectable,
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, focusedDay) =>
                          _buildAvailabilityCell(day),
                    ),
                    calendarStyle: CalendarStyle(
                      rangeHighlightColor: AppColors.saffron.withValues(
                        alpha: 0.15,
                      ),
                      rangeStartDecoration: const BoxDecoration(
                        color: AppColors.saffron,
                        shape: BoxShape.circle,
                      ),
                      rangeEndDecoration: const BoxDecoration(
                        color: AppColors.saffronDark,
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: AppColors.saffron.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: const BoxDecoration(
                        color: AppColors.saffron,
                        shape: BoxShape.circle,
                      ),
                      defaultTextStyle: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      weekendTextStyle: GoogleFonts.poppins(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                      selectedTextStyle: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      todayTextStyle: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      outsideTextStyle: GoogleFonts.poppins(
                        color: AppColors.textMuted.withValues(alpha: 0.4),
                      ),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      leftChevronIcon: const Icon(
                        Icons.chevron_left,
                        color: AppColors.textPrimary,
                      ),
                      rightChevronIcon: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: GoogleFonts.poppins(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      weekendStyle: GoogleFonts.poppins(
                        color: AppColors.saffron,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onRangeSelected: (start, end, _) => setState(() {
                      _checkIn = start;
                      _checkOut = end;
                    }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 4. Preferences ───────────────────────────────────
            _smallLabel('PREFERENCES'),
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bed type',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: ['Single', 'Double'].map((t) {
                      final sel = _bedType == t;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _bedType = t;
                            if (_guests > _maxGuests) _guests = _maxGuests;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: sel
                                  ? const LinearGradient(
                                      colors: [
                                        AppColors.saffron,
                                        AppColors.saffronDark,
                                      ],
                                    )
                                  : null,
                              color: sel ? null : AppColors.softSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel
                                    ? AppColors.saffron
                                    : AppColors.border,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                t,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 5. Guests & tents ───────────────────────────────
            _smallLabel('GUESTS & TENTS'),
            const SizedBox(height: 12),
            _card(
              child: Column(
                children: [
                  _counter(
                    'Guests',
                    'Max $_maxGuests with $_bedType bed × $_units tent${_units > 1 ? 's' : ''}',
                    _guests,
                    () {
                      if (_guests > 1) {
                        setState(() {
                          _guests--;
                          _clampChildren();
                        });
                      }
                    },
                    () {
                      if (_guests < _maxGuests) {
                        setState(() => _guests++);
                      } else {
                        _snack(
                          'Max $_maxGuests guests for $_units tent${_units > 1 ? 's' : ''} with $_bedType beds',
                          AppColors.error,
                        );
                      }
                    },
                  ),
                  _divider(),
                  _counter(
                    'Tents',
                    'Units to book ($_maxUnits available)',
                    _units,
                    () {
                      if (_units > 1) {
                        setState(() {
                          _units--;
                          if (_guests > _maxGuests) _guests = _maxGuests;
                          _clampChildren();
                        });
                      }
                    },
                    () {
                      if (_units < _maxUnits) {
                        setState(() => _units++);
                      } else {
                        _snack(
                          'Only $_maxUnits tent${_maxUnits > 1 ? 's' : ''} available',
                          AppColors.error,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 5b. Children ─────────────────────────────────────
            _smallLabel('TRAVELING WITH CHILDREN?'),
            const SizedBox(height: 12),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Are any guests children?',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _hasChildren,
                        onChanged: (v) => setState(() {
                          _hasChildren = v;
                          if (!v) {
                            _childrenUnder5 = 0;
                            _childrenAbove5 = 0;
                          }
                        }),
                        activeThumbColor: AppColors.saffron,
                        activeTrackColor: AppColors.saffron.withValues(
                          alpha: 0.35,
                        ),
                        inactiveThumbColor: AppColors.textMuted,
                        inactiveTrackColor: AppColors.border,
                      ),
                    ],
                  ),
                  if (_hasChildren) ...[
                    _divider(),
                    _counter(
                      'Below 5 yrs',
                      'Free · max $_maxChildrenUnder5 per tent',
                      _childrenUnder5,
                      () {
                        if (_childrenUnder5 > 0) {
                          setState(() => _childrenUnder5--);
                        }
                      },
                      () {
                        if (_childrenUnder5 >= _maxChildrenUnder5) {
                          _snack(
                            'Max $_maxChildrenUnder5 free young children per tent',
                            AppColors.error,
                          );
                        } else if (_childrenUnder5 + _childrenAbove5 >=
                            _maxTotalChildren) {
                          _snack(
                            'Children can\'t exceed total guests ($_maxTotalChildren)',
                            AppColors.error,
                          );
                        } else {
                          setState(() => _childrenUnder5++);
                        }
                      },
                    ),
                    _divider(),
                    _counter(
                      '5-12 yrs',
                      '₹${_childFeePerNight.toStringAsFixed(0)}/night each · max $_maxChildrenAbove5',
                      _childrenAbove5,
                      () {
                        if (_childrenAbove5 > 0) {
                          setState(() => _childrenAbove5--);
                        }
                      },
                      () {
                        if (_childrenAbove5 >= _maxChildrenAbove5) {
                          _snack(
                            'Max $_maxChildrenAbove5 children (5-12 yrs) per booking',
                            AppColors.error,
                          );
                        } else if (_childrenUnder5 + _childrenAbove5 >=
                            _maxTotalChildren) {
                          _snack(
                            'Children can\'t exceed total guests ($_maxTotalChildren)',
                            AppColors.error,
                          );
                        } else {
                          setState(() => _childrenAbove5++);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 6. Coupon ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _smallLabel('COUPON CODE'),
                TextButton.icon(
                  onPressed: () async {
                    final code = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const CouponsScreen(selectionMode: true),
                      ),
                    );
                    if (code != null) {
                      _couponController.text = code;
                      _applyCoupon();
                    }
                  },
                  icon: const Icon(
                    Icons.local_offer_outlined,
                    color: AppColors.saffron,
                    size: 16,
                  ),
                  label: Text(
                    'View All',
                    style: GoogleFonts.poppins(
                      color: AppColors.saffron,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Try: KUMBH10 · PILGRIM15 · FIRSTKUMBH · MAHASNAN',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _couponController,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Enter coupon code',
                      hintStyle: GoogleFonts.poppins(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: AppColors.softSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.saffron,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                  onPressed: _applyCoupon,
                  child: Text(
                    'APPLY',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            if (_couponApplied) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_appliedCouponCode applied — ${(_couponDiscountRate * 100).toStringAsFixed(0)}% off!',
                        style: GoogleFonts.poppins(
                          color: AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── 8. Price breakdown ──────────────────────────────
            if (_nights > 0) ...[
              _smallLabel('PRICE BREAKDOWN'),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  children: [
                    _priceRow(
                      '₹${widget.tent['price']} × $_nights nights × $_units tent',
                      '₹${_baseTotal.toStringAsFixed(0)}',
                    ),
                    if (_bedType == 'Double')
                      _priceRow(
                        'Double bed (+${(_doubleBedSurchargeRate * 100).toStringAsFixed(0)}%)',
                        '₹${_bedTypeSurcharge.toStringAsFixed(0)}',
                      ),
                    if (_hasChildren && _childrenAbove5 > 0)
                      _priceRow(
                        'Child fee (5-12 yrs) × $_childrenAbove5 × $_nights nights',
                        '₹${_childrenCharge.toStringAsFixed(0)}',
                      ),
                    if (_couponApplied)
                      _priceRow(
                        'Coupon (${(_couponDiscountRate * 100).toStringAsFixed(0)}%)',
                        '− ₹${_discount.toStringAsFixed(0)}',
                        isDiscount: true,
                      ),
                    _priceRow(
                      'CGST (${(_gstRate / 2 * 100).toStringAsFixed(0)}%)',
                      '₹${_cgst.toStringAsFixed(0)}',
                    ),
                    _priceRow(
                      'SGST (${(_gstRate / 2 * 100).toStringAsFixed(0)}%)',
                      '₹${_sgst.toStringAsFixed(0)}',
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(color: AppColors.border, thickness: 1),
                    ),
                    _priceRow(
                      'Total payable',
                      '₹${_grandTotal.toStringAsFixed(0)}',
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 110),
          ],
        ),
      ),

      // ── Bottom pay bar ──────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL PAYABLE',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    _nights > 0 ? '₹${_grandTotal.toStringAsFixed(0)}' : '—',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _isBooking
                    ? Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.textMuted.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      )
                    : PremiumButton(
                        label: _nights > 0
                            ? 'Proceed to pay'
                            : 'Select dates to continue',
                        verticalPadding: 16,
                        onPressed: _nights > 0 ? _proceedToPayment : null,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── UI helpers ────────────────────────────────────────────

  Widget _smallLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      t,
      style: GoogleFonts.poppins(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 1.4,
      ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.cardBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _divider() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Divider(color: AppColors.border, thickness: 1, height: 1),
  );

  Widget _datePill(String label, DateTime? date) {
    final months = [
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
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: date != null
              ? AppColors.saffron.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            date != null
                ? '${months[date.month]} ${date.day}, ${date.year}'
                : 'Select',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: date != null
                  ? AppColors.textPrimary
                  : AppColors.textMuted,
            ),
          ),
          if (date != null)
            Text(
              days[date.weekday - 1],
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.saffron,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (label == 'CHECK-OUT' && _nights > 0)
            Text(
              '$_nights nights',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.saffron,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    String hint,
    TextEditingController ctrl,
    TextInputType type, {
    String? errorText,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          onChanged: onChanged,
          inputFormatters: inputFormatters,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
            errorText: errorText,
            errorStyle: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.error,
            ),
            filled: true,
            fillColor: AppColors.softSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? AppColors.error : AppColors.border,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: hasError ? AppColors.error : AppColors.saffron,
                width: 1.8,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error, width: 1.8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _counter(
    String label,
    String sub,
    int value,
    VoidCallback minus,
    VoidCallback plus,
  ) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            sub,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
      Row(
        children: [
          _iconBtn(Icons.remove_rounded, minus, filled: false),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '$value',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _iconBtn(Icons.add_rounded, plus, filled: true),
        ],
      ),
    ],
  );

  Widget _iconBtn(IconData icon, VoidCallback cb, {required bool filled}) =>
      GestureDetector(
        onTap: cb,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: filled
                ? const LinearGradient(
                    colors: [AppColors.saffron, AppColors.saffronDark],
                  )
                : null,
            color: filled ? null : AppColors.softSurface,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: filled ? Colors.white : AppColors.saffron,
          ),
        ),
      );

  Widget _priceRow(
    String label,
    String value, {
    bool isDiscount = false,
    bool isTotal = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal,
              color: isTotal ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: isTotal ? 18 : 13,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
            color: isDiscount
                ? AppColors.success
                : isTotal
                ? AppColors.saffronDark
                : AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

/// Formats an Aadhaar number as it's typed into 4 groups of 4
/// digits (XXXX XXXX XXXX) and hard-caps input at 12 digits —
/// the field previously accepted unlimited free-form text.
class _AadhaarNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final allDigits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = allDigits.length > 12
        ? allDigits.substring(0, 12)
        : allDigits;

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i != 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
