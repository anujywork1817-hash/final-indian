import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/features/booking/screens/e_ticket_screen.dart';

class CancellationsScreen extends StatefulWidget {
  const CancellationsScreen({super.key});

  @override
  State<CancellationsScreen> createState() => _CancellationsScreenState();
}

class _CancellationsScreenState extends State<CancellationsScreen> {
  List<Map<String, dynamic>> _cancelled = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCancellations();
  }

  Future<void> _loadCancellations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ApiService.getMyBookings();
      final all = raw
          .map((b) => _normalize(b as Map<String, dynamic>))
          .toList();
      setState(() {
        _cancelled = all.where((b) => b['status'] == 'cancelled').toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load cancellations';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> b) {
    final colors = [
      const Color(0xFF7C3AED),
      const Color(0xFF0369A1),
      const Color(0xFF0891B2),
      const Color(0xFF065F46),
      const Color(0xFFB45309),
    ];
    final idx = (b['id'] ?? 0) % colors.length;
    List<String> images = [];
    if (b['images'] != null) images = List<String>.from(b['images']);
    return {
      'id': b['id'],
      'ref': b['booking_ref'] ?? b['ref'] ?? '',
      'tent': b['tent_name'] ?? b['tent'] ?? 'Tent',
      'tent_id': b['tent_id'],
      'location': b['location'] ?? '',
      'class': b['class'] ?? 'standard',
      'check_in': _formatDate(b['check_in']),
      'check_out': _formatDate(b['check_out']),
      'nights': b['nights'] ?? 0,
      'guests': b['guests'] ?? 1,
      'total': b['total_amount'] ?? b['total'] ?? 0,
      'status': b['status'] ?? 'pending',
      'payment_id': b['payment_id'],
      'color': colors[idx],
      'images': images,
    };
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw.toString());
      const m = [
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
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return raw.toString().split('T').first;
    }
  }

  Future<void> _clearOne(Map<String, dynamic> booking) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kLuxGoldSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Remove Booking?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: kDark),
        ),
        content: Text(
          'Remove ${booking['ref']} from your list?',
          style: GoogleFonts.poppins(fontSize: 13, color: kLuxMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No', style: GoogleFonts.poppins(color: kTrueSaffron)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
      await ApiService.deleteBooking(booking['ref']);
      setState(() => _cancelled.removeWhere((b) => b['ref'] == booking['ref']));
      if (mounted) _snack('Booking removed', Colors.green);
    } catch (e) {
      if (mounted) _snack('Failed to remove booking', Colors.red);
    }
  }

  Future<void> _clearAll() async {
    if (_cancelled.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kLuxGoldSoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear All?',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: kDark),
        ),
        content: Text(
          'Remove all ${_cancelled.length} cancelled booking(s)?',
          style: GoogleFonts.poppins(fontSize: 13, color: kLuxMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('No', style: GoogleFonts.poppins(color: kTrueSaffron)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
      for (final b in _cancelled) await ApiService.deleteBooking(b['ref']);
      setState(() => _cancelled.clear());
      if (mounted) _snack('All cleared', Colors.green);
    } catch (e) {
      if (mounted) _snack('Failed to clear some bookings', Colors.red);
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
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        title: Text(
          'Cancellations',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadCancellations,
          ),
          if (_cancelled.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.delete_sweep_outlined,
                color: Colors.white,
              ),
              onPressed: _clearAll,
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kTrueSaffron))
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('😕', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: GoogleFonts.poppins(fontSize: 15, color: kDark),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kTrueSaffron,
                    ),
                    onPressed: _loadCancellations,
                    child: Text(
                      'Retry',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                ],
              ),
            )
          : _cancelled.isEmpty
          ? RefreshIndicator(
              color: kTrueSaffron,
              onRefresh: _loadCancellations,
              child: ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Column(
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 60)),
                      const SizedBox(height: 16),
                      Text(
                        'No cancellations!',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: kDark,
                        ),
                      ),
                      Text(
                        'All your bookings are active.',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: kLuxMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: kTrueSaffron,
              onRefresh: _loadCancellations,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Refunds are processed within 5-7 business days to your original payment method.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._cancelled.map(
                    (b) =>
                        _CancelledCard(booking: b, onClear: () => _clearOne(b)),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CancelledCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onClear;
  const _CancelledCard({required this.booking, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: kLuxGoldSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: kTrueSaffron.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kTrueSaffron.withOpacity(0.15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.king_bed, color: kTrueSaffron, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking['tent'],
                        style: GoogleFonts.poppins(
                          color: kDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        booking['location'],
                        style: GoogleFonts.poppins(
                          color: kLuxMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Cancelled',
                    style: GoogleFonts.poppins(
                      color: Colors.red.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Dates row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoItem('Check-in', booking['check_in']),
                    _infoItem('Check-out', booking['check_out']),
                    _infoItem('Nights', '${booking['nights']}'),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: kLuxBorder, height: 1),
                const SizedBox(height: 12),

                // Refund status
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Refund Status',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: kLuxMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.hourglass_top,
                            color: Colors.orange,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Processing (5-7 business days)',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Ref + Amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Booking Ref',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: kLuxMuted,
                          ),
                        ),
                        Text(
                          booking['ref'],
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: kDark,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Amount Paid',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: kLuxMuted,
                          ),
                        ),
                        Text(
                          'Rs.${booking['total']}',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: kTrueSaffron),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ETicketScreen(booking: booking),
                          ),
                        ),
                        icon: Icon(
                          Icons.qr_code,
                          color: kTrueSaffron,
                          size: 16,
                        ),
                        label: Text(
                          'E-Ticket',
                          style: GoogleFonts.poppins(
                            color: kTrueSaffron,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: onClear,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 16,
                        ),
                        label: Text(
                          'Remove',
                          style: GoogleFonts.poppins(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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

  Widget _infoItem(String label, String value) => Column(
    children: [
      Text(label, style: GoogleFonts.poppins(fontSize: 10, color: kLuxMuted)),
      const SizedBox(height: 2),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: kDark,
        ),
      ),
    ],
  );
}
