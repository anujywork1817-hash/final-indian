import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/features/booking/screens/e_ticket_screen.dart';
import 'package:kumbh_tent/features/booking/screens/review_screen.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<dynamic> _bookings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ?? '';
      final phone = await storage.read(key: 'user_phone') ?? '';
      final res = await http.get(
        Uri.parse('$kBaseUrl/bookings'),
        headers: {'Authorization': 'Bearer $token', 'X-User-Phone': phone},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _bookings = (data['bookings'] ?? data) as List;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Could not load bookings';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _cancel(String ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kLuxGoldSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel Booking',
          style: GoogleFonts.playfairDisplay(
            color: kDark,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to cancel this booking?',
          style: GoogleFonts.poppins(color: kLuxMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'No',
              style: GoogleFonts.poppins(
                color: kTrueSaffron,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kTrueSaffron,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Yes, Cancel',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ?? '';
      final phone = await storage.read(key: 'user_phone') ?? '';
      await http.put(
        Uri.parse('$kBaseUrl/bookings/$ref/cancel'),
        headers: {'Authorization': 'Bearer $token', 'X-User-Phone': phone},
      );
      _load();
    } catch (_) {}
  }

  Future<void> _clear(String ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kLuxGoldSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove Booking?',
          style: GoogleFonts.playfairDisplay(
            color: kDark,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Remove this booking from your list?',
          style: GoogleFonts.poppins(color: kLuxMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No', style: GoogleFonts.poppins(color: kTrueSaffron)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Remove',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ?? '';
      final phone = await storage.read(key: 'user_phone') ?? '';
      await http.delete(
        Uri.parse('$kBaseUrl/bookings/$ref'),
        headers: {'Authorization': 'Bearer $token', 'X-User-Phone': phone},
      );
      setState(
        () => _bookings.removeWhere(
          (b) => (b['booking_ref'] ?? b['id'])?.toString() == ref,
        ),
      );
    } catch (_) {}
  }

  Future<void> _clearAll() async {
    final cancelled = _bookings
        .where(
          (b) => (b['status'] ?? '').toString().toLowerCase() == 'cancelled',
        )
        .toList();
    if (cancelled.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kLuxGoldSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear All Cancelled?',
          style: GoogleFonts.playfairDisplay(
            color: kDark,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Remove all ${cancelled.length} cancelled booking(s)?',
          style: GoogleFonts.poppins(color: kLuxMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No', style: GoogleFonts.poppins(color: kTrueSaffron)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear All',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ?? '';
      final phone = await storage.read(key: 'user_phone') ?? '';
      for (final b in cancelled) {
        final ref = (b['booking_ref'] ?? b['id'])?.toString() ?? '';
        await http.delete(
          Uri.parse('$kBaseUrl/bookings/$ref'),
          headers: {'Authorization': 'Bearer $token', 'X-User-Phone': phone},
        );
      }
      setState(
        () => _bookings.removeWhere(
          (b) => (b['status'] ?? '').toString().toLowerCase() == 'cancelled',
        ),
      );
    } catch (_) {}
  }

  List<dynamic> _filtered(String filter) {
    if (filter == 'all') return _bookings;
    return _bookings
        .where((b) => (b['status'] ?? '').toString().toLowerCase() == filter)
        .toList();
  }

  bool get _hasCancelled => _bookings.any(
    (b) => (b['status'] ?? '').toString().toLowerCase() == 'cancelled',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'My Bookings',
          style: GoogleFonts.playfairDisplay(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
          if (_hasCancelled)
            IconButton(
              icon: const Icon(
                Icons.delete_sweep_outlined,
                color: Colors.white,
              ),
              onPressed: _clearAll,
              tooltip: 'Clear All Cancelled',
            ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Active'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kTrueSaffron))
          : _error != null
          ? _empty(_error!)
          : TabBarView(
              controller: _tab,
              children: [_list('all'), _list('confirmed'), _list('completed')],
            ),
    );
  }

  Widget _list(String filter) {
    final items = _filtered(filter);
    if (items.isEmpty)
      return _empty('No ${filter == 'all' ? '' : filter} bookings yet');
    return RefreshIndicator(
      color: kTrueSaffron,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final ref =
              (items[i]['booking_ref'] ?? items[i]['id'])?.toString() ?? '';
          final status = (items[i]['status'] ?? '').toString().toLowerCase();
          return _BookingCard(
            booking: items[i],
            onCancel: () => _cancel(ref),
            onClear: () => _clear(ref),
            onTicket: () {
              final b = items[i];
              String fmtDate(dynamic iso) {
                if (iso == null) return '-';
                try {
                  final d = DateTime.parse(iso.toString());
                  return '${['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month]} ${d.day}, ${d.year}';
                } catch (_) {
                  return iso.toString();
                }
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ETicketScreen(
                    booking: {
                      'ref': b['booking_ref'] ?? b['id']?.toString() ?? '',
                      'tent': b['tent_name'] ?? '',
                      'location': b['location'] ?? '',
                      'class': b['class'] ?? '',
                      'check_in': fmtDate(b['check_in']),
                      'check_out': fmtDate(b['check_out']),
                      'nights': b['nights'] ?? 0,
                      'guests': b['guests'] ?? 1,
                      'total': (b['total_amount'] ?? b['total_price'] ?? 0)
                          .toString(),
                      'status': b['status'] ?? 'pending',
                      'payment_id': b['payment_id'] ?? '',
                    },
                  ),
                ),
              );
            },
            onReview: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReviewScreen(booking: items[i]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _empty(String msg) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.holiday_village_outlined,
          size: 64,
          color: kTrueSaffron.withOpacity(0.3),
        ),
        const SizedBox(height: 12),
        Text(msg, style: GoogleFonts.poppins(color: kLuxMuted, fontSize: 15)),
      ],
    ),
  );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onCancel;
  final VoidCallback onClear;
  final VoidCallback onTicket;
  final VoidCallback onReview;

  const _BookingCard({
    required this.booking,
    required this.onCancel,
    required this.onClear,
    required this.onTicket,
    required this.onReview,
  });

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month]} ${d.day}, ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  String get _status =>
      (booking['status'] ?? 'pending').toString().toLowerCase();

  Color get _badgeText {
    switch (_status) {
      case 'confirmed':
        return const Color(0xFF2E6B35);
      case 'cancelled':
        return const Color(0xFF8B1A1A);
      case 'pending':
        return const Color(0xFF7A4500);
      default:
        return kLuxMuted;
    }
  }

  Color get _badgeBg {
    switch (_status) {
      case 'confirmed':
        return const Color(0xFFDFF5E3);
      case 'cancelled':
        return const Color(0xFFF5E0E0);
      case 'pending':
        return const Color(0xFFFFF0D9);
      default:
        return kLuxGoldSoft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tentName = booking['tent_name'] ?? 'Tent';
    final location = booking['location'] ?? booking['tent_location'] ?? '';
    final checkIn = _fmt(booking['check_in']);
    final checkOut = _fmt(booking['check_out']);
    final ref = booking['booking_ref'] ?? booking['id'] ?? '—';
    final total = booking['total_price'] ?? booking['total_amount'] ?? 0;
    final cancelled = _status == 'cancelled';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: kLuxGoldSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kLuxBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: kTrueSaffron.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kTrueSaffron.withOpacity(0.12),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(17),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: kTrueSaffron.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.holiday_village_rounded,
                    color: kTrueSaffron,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tentName,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kDark,
                        ),
                      ),
                      if (location.isNotEmpty)
                        Text(
                          location,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: kLuxMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _badgeBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _status.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _badgeText,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Dates
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                Expanded(child: _col('CHECK-IN', checkIn)),
                Expanded(child: _col('CHECK-OUT', checkOut, end: true)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Divider(color: kLuxBorder, thickness: 1),
          ),

          // Ref + Total
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking ref',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: kLuxMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        ref.toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kDark,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total paid',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: kLuxMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      '₹${total.toString()}',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: kTrueSaffron,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onTicket,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kDark,
                          side: BorderSide(color: kLuxBorder, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: kLuxCream,
                        ),
                        child: Text(
                          'E-Ticket',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: kDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: cancelled ? onClear : onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cancelled
                              ? Colors.red
                              : const Color(0xFF8B1A1A),
                          side: BorderSide(
                            color: cancelled
                                ? Colors.red.shade300
                                : const Color(0xFFD4AAAA),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: kLuxCream,
                        ),
                        child: Text(
                          cancelled ? 'Clear' : 'Cancel',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!cancelled) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kTrueSaffron,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: Text(
                        'Rate & review your stay',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _col(String label, String value, {bool end = false}) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          color: kLuxMuted,
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: kDark,
        ),
      ),
    ],
  );
}
