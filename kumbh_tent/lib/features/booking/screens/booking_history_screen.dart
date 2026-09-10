import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/booking/screens/e_ticket_screen.dart';

/// Read-only list of EVERY booking the user has ever made, across all
/// statuses (pending, confirmed, completed, cancelled, …), newest
/// first. This is deliberately NOT `MyBookingsScreen` — no cancel /
/// clear / review actions, no status tabs — just a flat list where
/// tapping a booking goes straight to its e-ticket (QR + details).
///
/// Reused for two Profile entries via [title]: "History" and
/// "My E-Tickets" — same list, same tap-through, different heading.
class BookingHistoryScreen extends StatefulWidget {
  final String title;
  const BookingHistoryScreen({super.key, this.title = 'History'});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  List<dynamic> _bookings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.getMyBookings();
      // Newest first — fall back to check-in date if created_at is
      // missing on older rows.
      list.sort((a, b) {
        final ad = _parseDate(a['created_at']) ?? _parseDate(a['check_in']);
        final bd = _parseDate(b['created_at']) ?? _parseDate(b['check_in']);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      if (!mounted) return;
      setState(() {
        _bookings = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your booking history. Please try again.';
        _loading = false;
      });
    }
  }

  static DateTime? _parseDate(dynamic iso) {
    if (iso == null) return null;
    return DateTime.tryParse(iso.toString());
  }

  String _fmtDate(dynamic iso) {
    final d = _parseDate(iso);
    if (d == null) return '-';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  ({Color fg, Color bg, String label}) _statusStyle(String raw) {
    switch (raw.toLowerCase()) {
      case 'confirmed':
        return (
          fg: AppColors.success,
          bg: AppColors.success.withValues(alpha: 0.12),
          label: 'Confirmed',
        );
      case 'completed':
        return (
          fg: AppColors.classStandard,
          bg: AppColors.classStandard.withValues(alpha: 0.12),
          label: 'Completed',
        );
      case 'cancelled':
        return (
          fg: AppColors.error,
          bg: AppColors.error.withValues(alpha: 0.12),
          label: 'Cancelled',
        );
      case 'pending':
        return (
          fg: AppColors.warning,
          bg: AppColors.warning.withValues(alpha: 0.15),
          label: 'Pending',
        );
      default:
        return (
          fg: AppColors.textSecondary,
          bg: AppColors.softSurface,
          label: raw.isEmpty
              ? 'Unknown'
              : raw[0].toUpperCase() + raw.substring(1),
        );
    }
  }

  void _openTicket(Map<String, dynamic> b) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ETicketScreen(
          booking: {
            'ref': b['booking_ref'] ?? b['id']?.toString() ?? '',
            'tent': b['tent_name'] ?? '',
            'location': b['location'] ?? '',
            'class': b['class'] ?? '',
            'check_in': _fmtDate(b['check_in']),
            'check_out': _fmtDate(b['check_out']),
            'nights': b['nights'] ?? 0,
            'guests': b['guests'] ?? 1,
            'total': (b['total_amount'] ?? b['total_price'] ?? 0).toString(),
            'taxable_amount': ((b['base_amount'] ?? 0) as num).toDouble() -
                ((b['discount'] ?? 0) as num).toDouble(),
            'tax': ((b['tax'] ?? 0) as num).toDouble(),
            'status': b['status'] ?? 'pending',
            'payment_id': b['payment_id'] ?? '',
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          widget.title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.saffron),
      );
    }
    if (_error != null) {
      return _centered(
        icon: Icons.wifi_off_rounded,
        title: 'Something went wrong',
        subtitle: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (_bookings.isEmpty) {
      return _centered(
        icon: Icons.history_rounded,
        title: 'No bookings yet',
        subtitle: 'Your booking history will appear here.',
      );
    }
    return RefreshIndicator(
      color: AppColors.saffron,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _bookings.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) =>
            _historyCard(_bookings[i] as Map<String, dynamic>),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> b) {
    final status = _statusStyle((b['status'] ?? '').toString());
    final ref = (b['booking_ref'] ?? b['id'])?.toString() ?? '';
    final total = (b['total_amount'] ?? b['total_price'] ?? 0);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openTicket(b),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (b['tent_name'] ?? 'Tent Booking').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: status.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.label,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: status.fg,
                      ),
                    ),
                  ),
                ],
              ),
              if ((b['location'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  b['location'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_fmtDate(b['check_in'])}  →  ${_fmtDate(b['check_out'])}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.confirmation_number_outlined,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ref,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '₹$total',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.saffronDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centered({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 8), action],
          ],
        ),
      ),
    );
  }
}
