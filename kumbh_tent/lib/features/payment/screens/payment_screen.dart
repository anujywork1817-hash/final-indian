import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/booking/screens/e_ticket_screen.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic> tent;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final int units;
  final double totalAmount;
  final String? couponCode;
  final String bookingRef;

  /// Taxable amount (base − discount) and GST already computed by
  /// the server for this booking — carried through so the e-ticket
  /// can show the CGST/SGST split without re-deriving it.
  final double taxableAmount;
  final double tax;

  const PaymentScreen({
    super.key,
    required this.tent,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.units,
    required this.totalAmount,
    required this.bookingRef,
    required this.taxableAmount,
    required this.tax,
    this.couponCode,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  late Razorpay _razorpay;
  bool _isProcessing = false;
  String _selectedMethod = 'upi';
  String _userPhone = '';
  String _authToken = '';

  static const _storage = FlutterSecureStorage();
  // Razorpay publishable Key ID. Provide it at build time with
  //   flutter build apk --dart-define=RAZORPAY_KEY_ID=rzp_...
  // so the credential isn't committed to source. It MUST match
  // RAZORPAY_KEY_ID on the backend — the SDK opens checkout with
  // this key while the order was created server-side with the same
  // account's key, and a mismatch fails immediately with a generic
  // "Payment Failed".
  //
  // A test-mode default is kept so existing builds keep working; CI
  // should always pass the define and this fallback should be dropped
  // once that's in place (BUG-19).
  static const String _razorpayKey = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: 'rzp_test_TZnmTJ5wGDBox2',
  );

  int get _nights => widget.checkOut.difference(widget.checkIn).inDays;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  Future<void> _loadCredentials() async {
    // BUG-09: verifyOTP() writes the phone/token to FlutterSecureStorage,
    // not SharedPreferences — reading prefs here left _userPhone empty, so
    // every payment call went out with a blank X-User-Phone header and was
    // rejected. Read from the same store ApiService writes to.
    final phone = await _storage.read(key: kUserPhone);
    final token = await _storage.read(key: kAuthToken);
    setState(() {
      _userPhone = phone ?? '';
      _authToken = token ?? '';
    });
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $_authToken',
    'X-User-Phone': _userPhone,
  };

  // ── WhatsApp Confirmation ─────────────────────────────────
  Future<void> _sendWhatsAppConfirmation({required String status}) async {
    final checkIn =
        '${widget.checkIn.day} ${_monthName(widget.checkIn.month)} ${widget.checkIn.year}';
    final checkOut =
        '${widget.checkOut.day} ${_monthName(widget.checkOut.month)} ${widget.checkOut.year}';
    final paymentStatus = status == 'confirmed'
        ? '✅ Paid Online'
        : '⏳ Pay at Tent (Cash)';

    final message =
        '''
🪔 *Kumbh Tent Booking Confirmed!*

📋 *Booking Details:*
• Ref: *${widget.bookingRef}*
• Tent: ${widget.tent['name']}
• Location: ${widget.tent['location']}
• Check-in: $checkIn
• Check-out: $checkOut
• Nights: $_nights
• Guests: ${widget.guests}

💰 *Amount: ₹${widget.totalAmount.toStringAsFixed(0)}*
💳 *Payment: $paymentStatus*

🏕️ Show this message or your E-Ticket QR code at the camp entrance.

*Nashik Kumbh 2027* 🙏
''';

    final encoded = Uri.encodeComponent(message);
    String storedPhone = await _storage.read(key: kUserPhone) ?? '';
    if (storedPhone.isEmpty) storedPhone = _userPhone;
    final phone = storedPhone
        .replaceAll('+', '')
        .replaceAll(' ', '')
        .replaceAll('-', '');
    if (phone.isEmpty || phone.length < 10) return;
    final whatsappPhone = phone.startsWith('91') ? phone : '91$phone';
    final uri = Uri.parse('https://wa.me/$whatsappPhone?text=$encoded');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Pay at Tent (Cash) ────────────────────────────────────
  void _payAtTent() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirm Cash Payment',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have chosen to pay at the tent on arrival.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.goldWarm.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.goldWarm.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Please note:',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.saffronDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Amount due: ₹${widget.totalAmount.toStringAsFixed(0)}\n'
                    '• Pay in cash at check-in\n'
                    '• Booking may be cancelled if not paid\n'
                    '• Bring this e-ticket to the camp',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _goToETicket(status: 'pending', paymentId: 'CASH');
              // Send WhatsApp confirmation
              Future.delayed(const Duration(seconds: 2), () {
                _sendWhatsAppConfirmation(status: 'pending');
              });
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _goToETicket({required String status, required String paymentId}) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => ETicketScreen(
          booking: {
            'ref': widget.bookingRef,
            'tent': widget.tent['name'],
            'location': widget.tent['location'],
            'class': widget.tent['class'],
            'check_in':
                '${widget.checkIn.day} ${_monthName(widget.checkIn.month)}, ${widget.checkIn.year}',
            'check_out':
                '${widget.checkOut.day} ${_monthName(widget.checkOut.month)}, ${widget.checkOut.year}',
            'nights': _nights,
            'guests': widget.guests,
            'total': widget.totalAmount.toStringAsFixed(0),
            'taxable_amount': widget.taxableAmount,
            'tax': widget.tax,
            'status': status,
            'payment_id': paymentId,
          },
        ),
      ),
      (route) => route.isFirst,
    );
  }

  // ── Online Payment ────────────────────────────────────────
  Future<void> _startPayment() async {
    setState(() => _isProcessing = true);
    try {
      final res = await http.post(
        Uri.parse('$kBaseUrl/orders/create'),
        headers: _headers,
        body: jsonEncode({
          'booking_ref': widget.bookingRef,
          'amount': widget.totalAmount,
        }),
      );

      if (res.statusCode != 200) {
        throw Exception('Failed to create order: ${res.body}');
      }

      final order = jsonDecode(res.body);
      final razorpayOrderId = order['razorpay_order_id'];

      if (razorpayOrderId == null || razorpayOrderId.isEmpty) {
        throw Exception('Invalid order ID received from server');
      }

      final options = {
        'key': _razorpayKey,
        'order_id': razorpayOrderId,
        'amount': (widget.totalAmount * 100).toInt(),
        'name': 'Kumbh Tent Booking',
        'description':
            '${widget.tent['name']} • $_nights nights • ${widget.guests} guests',
        'prefill': {'contact': _userPhone, 'email': ''},
        'theme': {'color': '#E85D04'},
        'notes': {
          'booking_ref': widget.bookingRef,
          'tent_id': widget.tent['id']?.toString() ?? '',
          'check_in': widget.checkIn.toIso8601String(),
          'check_out': widget.checkOut.toIso8601String(),
        },
      };

      _razorpay.open(options);
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', style: GoogleFonts.poppins()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final res = await http.post(
        Uri.parse('$kBaseUrl/payments/verify'),
        headers: _headers,
        body: jsonEncode({
          'booking_ref': widget.bookingRef,
          'razorpay_payment_id': response.paymentId,
          'razorpay_order_id': response.orderId,
          'razorpay_signature': response.signature,
        }),
      );

      setState(() => _isProcessing = false);

      if (res.statusCode != 200) {
        throw Exception('Verification failed: ${res.body}');
      }

      if (mounted) {
        _goToETicket(status: 'confirmed', paymentId: response.paymentId ?? '');
        // Send WhatsApp confirmation after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          _sendWhatsAppConfirmation(status: 'confirmed');
        });
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Verification error: $e',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Payment failed: ${response.message}',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'External wallet: ${response.walletName}',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: AppColors.saffron,
      ),
    );
  }

  String _monthName(int month) {
    const months = [
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
    return months[month - 1];
  }

  void _onProceed() {
    if (_selectedMethod == 'cash') {
      _payAtTent();
    } else {
      _startPayment();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Payment',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Order Summary ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Order Summary',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.saffron, AppColors.goldWarm],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: Text('⛺', style: TextStyle(fontSize: 24)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.tent['name'],
                              style: GoogleFonts.poppins(
                                fontSize: 14,
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
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: AppColors.border),
                  const SizedBox(height: 14),
                  _summaryRow(
                    '📅 Check-in',
                    '${widget.checkIn.day} ${_monthName(widget.checkIn.month)} ${widget.checkIn.year}',
                  ),
                  _summaryRow(
                    '📅 Check-out',
                    '${widget.checkOut.day} ${_monthName(widget.checkOut.month)} ${widget.checkOut.year}',
                  ),
                  _summaryRow('🌙 Nights', '$_nights'),
                  _summaryRow('👥 Guests', '${widget.guests}'),
                  _summaryRow('⛺ Tents', '${widget.units}'),
                  if (widget.couponCode != null)
                    _summaryRow('🎟 Coupon', widget.couponCode!),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: AppColors.border, height: 1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '₹${widget.totalAmount.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.saffronDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'Payment Method',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            Container(
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
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _paymentMethodTile(
                    key: 'upi',
                    icon: '📱',
                    title: 'UPI',
                    subtitle: 'GPay, PhonePe, Paytm & more',
                  ),
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppColors.border,
                  ),
                  _paymentMethodTile(
                    key: 'card',
                    icon: '💳',
                    title: 'Credit / Debit Card',
                    subtitle: 'Visa, Mastercard, RuPay',
                  ),
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppColors.border,
                  ),
                  _paymentMethodTile(
                    key: 'netbanking',
                    icon: '🏦',
                    title: 'Net Banking',
                    subtitle: 'All major banks supported',
                  ),
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppColors.border,
                  ),
                  _paymentMethodTile(
                    key: 'wallet',
                    icon: '👛',
                    title: 'Wallets',
                    subtitle: 'Paytm, Amazon Pay & more',
                  ),
                  const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: AppColors.border,
                  ),
                  _paymentMethodTile(
                    key: 'cash',
                    icon: '💵',
                    title: 'Pay at Tent',
                    subtitle: 'Pay cash on arrival at camp',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_selectedMethod == 'cash')
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.goldWarm.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.goldWarm.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.saffronDark,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You will receive a booking confirmation on WhatsApp. Pay ₹${widget.totalAmount.toStringAsFixed(0)} in cash at check-in.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.success,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '100% secure payment powered by Razorpay. Booking confirmation will be sent on WhatsApp.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 100),
          ],
        ),
      ),

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
          child: _isProcessing
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
                  label: _selectedMethod == 'cash'
                      ? 'Confirm — Pay ₹${widget.totalAmount.toStringAsFixed(0)} at Tent 🪔'
                      : 'Pay ₹${widget.totalAmount.toStringAsFixed(0)} Online 🪔',
                  verticalPadding: 16,
                  onPressed: _onProceed,
                ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );

  Widget _paymentMethodTile({
    required String key,
    required String icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedMethod == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.saffron.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.saffron.withValues(alpha: 0.12)
                    : AppColors.softSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 19)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.saffron : AppColors.border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Container(
                      margin: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.saffron, AppColors.saffronDark],
                        ),
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
