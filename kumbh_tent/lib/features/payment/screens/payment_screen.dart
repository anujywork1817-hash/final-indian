import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/features/booking/screens/e_ticket_screen.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic> tent;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final int units;
  final double totalAmount;
  final String? couponCode;
  final String bookingRef;

  const PaymentScreen({
    super.key,
    required this.tent,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.units,
    required this.totalAmount,
    required this.bookingRef,
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
  static const String _razorpayKey = 'rzp_test_SqpASBdCN2DXd0';

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
    final prefs = await SharedPreferences.getInstance();
    final token = await _storage.read(key: kAuthToken);
    setState(() {
      _userPhone = prefs.getString(kUserPhone) ?? '';
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
    // Read phone from secure storage first, then SharedPreferences
    String storedPhone = await _storage.read(key: 'user_phone') ?? '';
    if (storedPhone.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      storedPhone = prefs.getString(kUserPhone) ?? '';
    }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Confirm Cash Payment',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You have chosen to pay at the tent on arrival.',
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Please note:',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade800,
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
                      color: Colors.orange.shade900,
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
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kSaffron,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _goToETicket(status: 'pending', paymentId: 'CASH');
              // Send WhatsApp confirmation
              Future.delayed(const Duration(seconds: 2), () {
                _sendWhatsAppConfirmation(status: 'pending');
              });
            },
            child: Text(
              'Confirm',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
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
        'theme': {'color': '#FF6B00'},
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
            backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
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
        backgroundColor: Colors.red,
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
        backgroundColor: kSaffron,
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
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kDeepOrange,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Payment',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Order Summary ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 10,
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
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: (widget.tent['color'] as Color).withAlpha(40),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text('⛺', style: TextStyle(fontSize: 26)),
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
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kDark,
                              ),
                            ),
                            Text(
                              widget.tent['location'],
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
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
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kDark,
                        ),
                      ),
                      Text(
                        '₹${widget.totalAmount.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: kSaffron,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Payment Method',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: kDark,
              ),
            ),
            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _paymentMethodTile(
                    key: 'upi',
                    icon: '📱',
                    title: 'UPI',
                    subtitle: 'GPay, PhonePe, Paytm & more',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _paymentMethodTile(
                    key: 'card',
                    icon: '💳',
                    title: 'Credit / Debit Card',
                    subtitle: 'Visa, Mastercard, RuPay',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _paymentMethodTile(
                    key: 'netbanking',
                    icon: '🏦',
                    title: 'Net Banking',
                    subtitle: 'All major banks supported',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _paymentMethodTile(
                    key: 'wallet',
                    icon: '👛',
                    title: 'Wallets',
                    subtitle: 'Paytm, Amazon Pay & more',
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withAlpha(50)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You will receive a booking confirmation on WhatsApp. Pay ₹${widget.totalAmount.toStringAsFixed(0)} in cash at check-in.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withAlpha(50)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline_rounded,
                      color: Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '100% secure payment powered by Razorpay. Booking confirmation will be sent on WhatsApp.',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 80),
          ],
        ),
      ),

      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kSaffron,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _isProcessing ? null : _onProceed,
          child: _isProcessing
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  _selectedMethod == 'cash'
                      ? 'Confirm — Pay ₹${widget.totalAmount.toStringAsFixed(0)} at Tent 🪔'
                      : 'Pay ₹${widget.totalAmount.toStringAsFixed(0)} Online 🪔',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
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
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kDark,
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
    final isCash = key == 'cash';
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isCash ? Colors.orange.withAlpha(15) : kSaffron.withAlpha(10))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
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
                      color: kDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey,
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
                  color: isSelected
                      ? (isCash ? Colors.orange : kSaffron)
                      : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Container(
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isCash ? Colors.orange : kSaffron,
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
