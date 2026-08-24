import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/features/payment/screens/payment_screen.dart';
import 'package:kumbh_tent/features/booking/screens/coupons_screen.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';
import 'package:kumbh_tent/features/booking/widgets/cancellation_policy_badge.dart';

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

  // Airport/station pickup and puja kit add-ons were removed from
  // the booking form. Their state, charges, price rows and
  // booking payload keys went with them so no hidden ₹0 line
  // items or dead flags remain.
  bool _godavariWalk = false;
  bool _prasadThali = false;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
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
  double get _godavariCharge => _godavariWalk ? _guests * 300.0 : 0;
  double get _prasadCharge => _prasadThali ? _guests * 150.0 : 0;
  double get _addonsTotal => _godavariCharge + _prasadCharge;
  double get _subtotal => _baseTotal + _addonsTotal;
  double get _discount => _couponApplied ? _subtotal * _couponDiscountRate : 0;
  double get _taxableAmount => _subtotal - _discount;
  double get _gstRate => gstRateFor(_taxableAmount);
  double get _tax => _taxableAmount * _gstRate;
  double get _cgst => _tax / 2;
  double get _sgst => _tax / 2;
  double get _grandTotal => _subtotal - _discount + _tax;

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
        _snack(res['message'] ?? 'Coupon applied!', Colors.green);
      } else {
        setState(() {
          _couponApplied = false;
          _appliedCouponCode = '';
          _couponDiscountRate = 0;
        });
        _snack(res['message'] ?? 'Invalid coupon', Colors.red);
      }
    } catch (_) {
      _snack('Could not validate coupon', Colors.red);
    }
  }

  Future<void> _proceedToPayment() async {
    if (_nameController.text.trim().isEmpty) {
      _snack('Please enter guest name', Colors.red);
      return;
    }
    if (_phoneController.text.trim().length < 10) {
      _snack('Please enter a valid phone number', Colors.red);
      return;
    }
    if (_idProofController.text.trim().isEmpty) {
      _snack('Please enter ID proof number', Colors.red);
      return;
    }
    if (_checkIn == null || _checkOut == null) {
      _snack('Please select dates', Colors.red);
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
          'bed_type': _bedType,
          'gender_preference': _genderPreference,
          'godavari_walk': _godavariWalk,
          'prasad_thali': _prasadThali,
        },
      );
      final serverBooking = result['booking'] as Map<String, dynamic>;
      final bookingRef = serverBooking['booking_ref'] as String;
      final serverBase = (serverBooking['base_amount'] as num).toDouble();
      final serverDiscount = (serverBooking['discount'] as num).toDouble();
      final serverTax = (serverBooking['tax'] as num).toDouble();
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
            e.toString().contains('not available'))
          msg = '🚫 Tent already booked for selected dates.';
        else if (e.toString().contains('400'))
          msg = 'Invalid booking details.';
        else if (e.toString().contains('401'))
          msg = 'Session expired. Please login again.';
        _snack(msg, Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isBooking = false);
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
      backgroundColor: kTrueSaffronPale,

      // ── AppBar — saffron, matches mockup exactly ───────────
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              'Book Your Tent',
              style: GoogleFonts.playfairDisplay(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            Text(
              'KUMBH MELA · NASHIK 2027',
              style: GoogleFonts.poppins(
                color: Colors.white70,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Tent card ────────────────────────────────────
            _card(
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
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
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kDark,
                          ),
                        ),
                        Text(
                          widget.tent['location'],
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: kLuxMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${widget.tent['price']} / night',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: kTrueSaffron,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 2. Guest details ────────────────────────────────
            _smallLabel('GUEST DETAILS'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  _field(
                    'Full name',
                    'Kumbh User',
                    _nameController,
                    TextInputType.name,
                  ),
                  _divider(),
                  _field(
                    'Mobile number',
                    '+91 9876543210',
                    _phoneController,
                    TextInputType.phone,
                  ),
                  _divider(),
                  _field(
                    'ID proof (Aadhaar / Passport)',
                    'Enter number',
                    _idProofController,
                    TextInputType.text,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 3. Select dates ─────────────────────────────────
            _smallLabel('SELECT DATES'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  // Date pills matching mockup
                  Row(
                    children: [
                      Expanded(child: _datePill('CHECK-IN', _checkIn)),
                      const SizedBox(width: 10),
                      Expanded(child: _datePill('CHECK-OUT', _checkOut)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Calendar
                  TableCalendar(
                    firstDay: DateTime.now(),
                    lastDay: DateTime(2027, 10, 31),
                    focusedDay: _checkIn ?? DateTime(2027, 8, 1),
                    rangeStartDay: _checkIn,
                    rangeEndDay: _checkOut,
                    rangeSelectionMode: RangeSelectionMode.toggledOn,
                    calendarStyle: CalendarStyle(
                      rangeHighlightColor: kTrueSaffron.withOpacity(0.15),
                      rangeStartDecoration: const BoxDecoration(
                        color: kTrueSaffron,
                        shape: BoxShape.circle,
                      ),
                      rangeEndDecoration: const BoxDecoration(
                        color: kTrueSaffronDark,
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: kTrueSaffron.withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: const BoxDecoration(
                        color: kTrueSaffron,
                        shape: BoxShape.circle,
                      ),
                      defaultTextStyle: GoogleFonts.poppins(
                        color: kDark,
                        fontSize: 13,
                      ),
                      weekendTextStyle: GoogleFonts.poppins(
                        color: kLuxMuted,
                        fontSize: 13,
                      ),
                      selectedTextStyle: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      todayTextStyle: GoogleFonts.poppins(
                        color: kDark,
                        fontWeight: FontWeight.w700,
                      ),
                      outsideTextStyle: GoogleFonts.poppins(
                        color: kLuxMuted.withOpacity(0.4),
                      ),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: kDark,
                      ),
                      leftChevronIcon: Icon(Icons.chevron_left, color: kDark),
                      rightChevronIcon: Icon(Icons.chevron_right, color: kDark),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: GoogleFonts.poppins(
                        color: kLuxMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      weekendStyle: GoogleFonts.poppins(
                        color: kTrueSaffron,
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

            const SizedBox(height: 20),

            // ── 4. Guests & tents ───────────────────────────────
            _smallLabel('GUESTS & TENTS'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  _counter(
                    'Guests',
                    'Max 4 per tent',
                    _guests,
                    () {
                      if (_guests > 1) setState(() => _guests--);
                    },
                    () => setState(() => _guests++),
                  ),
                  _divider(),
                  _counter('Tents', 'Units to book', _units, () {
                    if (_units > 1) setState(() => _units--);
                  }, () => setState(() => _units++)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 5. Preferences ──────────────────────────────────
            _smallLabel('PREFERENCES'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bed type',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: ['Single', 'Double'].map((t) {
                      final sel = _bedType == t;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _bedType = t),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: sel
                                  ? kTrueSaffron
                                  : kTrueSaffron.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel
                                    ? kTrueSaffronDark
                                    : kTrueSaffron.withOpacity(0.3),
                                width: sel ? 1.5 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                t,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel ? Colors.white : kDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: kTrueSaffron.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wc_outlined, color: kTrueSaffron, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Gender preference: $_genderPreference',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: kDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'set at signup',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: kLuxMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 6. Pilgrim services ─────────────────────────────
            _smallLabel('PILGRIM SERVICES'),
            const SizedBox(height: 10),
            _card(
              child: Column(
                children: [
                  _toggle(
                    '🚶 Guided Godavari walk',
                    '+ ₹300 per person',
                    _godavariWalk,
                    (v) => setState(() => _godavariWalk = v),
                  ),
                  _divider(),
                  _toggle(
                    '🍱 Prasad thali',
                    '+ ₹150 per person',
                    _prasadThali,
                    (v) => setState(() => _prasadThali = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── 7. Coupon ───────────────────────────────────────
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
                  icon: Icon(
                    Icons.local_offer_outlined,
                    color: kTrueSaffron,
                    size: 16,
                  ),
                  label: Text(
                    'View All',
                    style: GoogleFonts.poppins(
                      color: kTrueSaffron,
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
              style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _couponController,
                    style: GoogleFonts.poppins(fontSize: 14, color: kDark),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Enter coupon code',
                      hintStyle: GoogleFonts.poppins(
                        color: kLuxMuted,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: kLuxCream,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: kLuxBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: kLuxBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: kTrueSaffron,
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
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kTrueSaffron,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                    elevation: 0,
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
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$_appliedCouponCode applied — ${(_couponDiscountRate * 100).toStringAsFixed(0)}% off!',
                      style: GoogleFonts.poppins(
                        color: Colors.green.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            CancellationPolicyBadge(tent: widget.tent),
            const SizedBox(height: 20),

            // ── 8. Price breakdown ──────────────────────────────
            if (_nights > 0) ...[
              _smallLabel('PRICE BREAKDOWN'),
              const SizedBox(height: 10),
              _card(
                child: Column(
                  children: [
                    _priceRow(
                      '₹${widget.tent['price']} × $_nights nights × $_units tent',
                      '₹${_baseTotal.toStringAsFixed(0)}',
                    ),
                    if (_godavariWalk)
                      _priceRow(
                        'Guided Godavari walk',
                        '₹${_godavariCharge.toStringAsFixed(0)}',
                      ),
                    if (_prasadThali)
                      _priceRow(
                        'Prasad thali',
                        '₹${_prasadCharge.toStringAsFixed(0)}',
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(color: kLuxBorder, thickness: 1),
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

            const SizedBox(height: 100),
          ],
        ),
      ),

      // ── Bottom pay bar — matches mockup ────────────────────
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 50),
        decoration: BoxDecoration(
          color: kTrueSaffron,
          boxShadow: [
            BoxShadow(
              color: kTrueSaffronDark.withOpacity(0.4),
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
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  _nights > 0 ? '₹${_grandTotal.toStringAsFixed(0)}' : '—',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: GestureDetector(
                onTap: (_nights > 0 && !_isBooking) ? _proceedToPayment : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 52,
                  decoration: BoxDecoration(
                    color: _nights > 0
                        ? kTrueSaffronDark
                        : kTrueSaffronDark.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _nights > 0
                        ? [
                            BoxShadow(
                              color: kTrueSaffronDark.withOpacity(0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Center(
                    child: _isBooking
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            _nights > 0
                                ? 'Proceed to pay'
                                : 'Select dates to continue',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
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
        color: kLuxMuted,
        letterSpacing: 1.4,
      ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: kLuxGoldSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kLuxBorder, width: 1.2),
      boxShadow: [
        BoxShadow(
          color: kTrueSaffron.withOpacity(0.06),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Divider(color: kLuxBorder, thickness: 1, height: 1),
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
        color: kLuxCream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: date != null ? kTrueSaffron.withOpacity(0.5) : kLuxBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: kLuxMuted,
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
              color: date != null ? kDark : kLuxMuted,
            ),
          ),
          if (date != null)
            Text(
              days[date.weekday - 1],
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: kTrueSaffron,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (label == 'CHECK-OUT' && _nights > 0)
            Text(
              '$_nights nights',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: kTrueSaffron,
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
    TextInputType type,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: kLuxMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: type,
        style: GoogleFonts.poppins(fontSize: 14, color: kDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(
            color: kLuxMuted.withOpacity(0.7),
            fontSize: 13,
          ),
          filled: true,
          fillColor: kLuxCream,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: kLuxBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: kLuxBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kTrueSaffron, width: 1.8),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
      ),
    ],
  );

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
              color: kDark,
            ),
          ),
          Text(sub, style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted)),
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
                fontWeight: FontWeight.w800,
                color: kDark,
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
            color: filled ? kTrueSaffron : kTrueSaffron.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: filled ? Colors.white : kTrueSaffron,
          ),
        ),
      );

  Widget _toggle(
    String label,
    String sub,
    bool value,
    ValueChanged<bool> onChange,
  ) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kDark,
            ),
          ),
          Text(sub, style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted)),
        ],
      ),
      Switch.adaptive(
        value: value,
        onChanged: onChange,
        activeColor: kTrueSaffron,
        activeTrackColor: kTrueSaffron.withOpacity(0.35),
        inactiveThumbColor: kLuxMuted,
        inactiveTrackColor: kLuxBorder,
      ),
    ],
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
              color: isTotal ? kDark : kLuxMuted,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: isTotal ? 18 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
            color: isDiscount
                ? Colors.green
                : isTotal
                ? kTrueSaffron
                : kDark,
          ),
        ),
      ],
    ),
  );
}
