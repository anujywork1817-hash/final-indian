import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/booking/screens/e_ticket_screen.dart';
import 'package:kumbh_tent/features/booking/widgets/refund_status_panel.dart';
import 'package:kumbh_tent/shared/widgets/premium_badge.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';
import 'package:kumbh_tent/shared/widgets/shimmer_tent_card.dart';

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
      'taxable_amount':
          ((b['base_amount'] ?? 0) as num).toDouble() -
          ((b['discount'] ?? 0) as num).toDouble(),
      'tax': ((b['tax'] ?? 0) as num).toDouble(),
      'status': b['status'] ?? 'pending',
      'payment_id': b['payment_id'],
      'color': colors[idx],
      'images': images,
      // Real refund state from the backend. Absent when no
      // refund was recorded for this booking.
      'refund_status': b['refund_status'],
      'refund_amount': b['refund_amount'],
      'refund_message': b['refund_message'],
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

  Future<void> _clearAll() async {
    if (_cancelled.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear All?',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Remove all ${_cancelled.length} cancelled booking(s)?',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'No',
              style: GoogleFonts.poppins(color: AppColors.saffron),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
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
      for (final b in _cancelled) {
        await ApiService.deleteBooking(b['ref']);
      }
      setState(() => _cancelled.clear());
      if (mounted) _snack('All cleared', AppColors.success);
    } catch (e) {
      if (mounted) _snack('Failed to clear some bookings', AppColors.error);
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Cancellations',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadCancellations,
          ),
          if (_cancelled.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
              tooltip: 'Clear All',
            ),
        ],
      ),
      body: _loading
          ? ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 3,
              itemBuilder: (context, i) => const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: SizedBox(height: 260, child: ShimmerTentCard()),
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 160,
                      child: PremiumButton(
                        label: 'Retry',
                        onPressed: _loadCancellations,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _cancelled.isEmpty
          ? RefreshIndicator(
              color: AppColors.saffron,
              onRefresh: _loadCancellations,
              child: ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 48,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No cancellations',
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'All your bookings are active.',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: AppColors.saffron,
              onRefresh: _loadCancellations,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.goldWarm.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.goldWarm.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.goldWarm.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.goldWarm,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Refund requests are reviewed by our team. Once approved, '
                            'the amount is credited to your original payment method '
                            'within 3-4 working days.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._cancelled.asMap().entries.map(
                    (entry) => TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 280 + (entry.key * 60)),
                      curve: Curves.easeOut,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, (1 - value) * 14),
                          child: child,
                        ),
                      ),
                      child: _CancelledCard(booking: entry.value),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CancelledCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _CancelledCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: AppColors.error),
            Expanded(
              child: Column(
                children: [
                  // Card header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.king_bed_rounded,
                            color: AppColors.error,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                booking['tent'],
                                style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                booking['location'],
                                style: GoogleFonts.poppins(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PremiumBadge(
                          label: 'CANCELLED',
                          style: PremiumBadgeStyle.danger,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),

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
                        const SizedBox(height: 14),
                        const Divider(color: AppColors.border, height: 1),
                        const SizedBox(height: 14),

                        // Refund status — driven by the backend's real
                        // refund record, not a hardcoded label.
                        RefundStatusPanel(booking: booking),
                        const SizedBox(height: 14),

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
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                Text(
                                  booking['ref'],
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
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
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                Text(
                                  '₹${booking['total']}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Action button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ETicketScreen(booking: booking),
                              ),
                            ),
                            icon: const Icon(Icons.qr_code_rounded, size: 16),
                            label: const Text('E-Ticket'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoItem(String label, String value) => Column(
    children: [
      Text(
        label,
        style: GoogleFonts.poppins(fontSize: 10, color: AppColors.textMuted),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    ],
  );
}
