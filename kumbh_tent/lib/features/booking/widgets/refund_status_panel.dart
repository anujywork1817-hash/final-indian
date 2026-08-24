import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/constants/constants.dart';

/// Renders the refund state the backend actually recorded for a
/// cancelled booking.
///
/// Before this existed, the Cancellations screen unconditionally
/// displayed "Processing (5-7 business days)" on every cancelled
/// booking — regardless of whether a refund had been created,
/// attempted, or completed, and while the backend had no refund
/// pipeline at all.
///
/// Reads three fields the bookings API now returns:
/// `refund_status`, `refund_amount`, `refund_message`.
class RefundStatusPanel extends StatelessWidget {
  final Map<String, dynamic> booking;
  const RefundStatusPanel({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final status = booking['refund_status'] as String?;
    final amount = (booking['refund_amount'] as num?)?.toDouble() ?? 0;
    final message = booking['refund_message'] as String?;

    final v = visualsFor(status);

    // A declined request must not display the amount as a
    // headline figure — nothing is coming, and showing it reads
    // as a promise.
    final showAmount = amount > 0 && status != 'rejected';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: v.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: v.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Refund Status',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: kLuxMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showAmount)
                Text(
                  'Rs.${amount.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: v.foreground,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(v.icon, color: v.foreground, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  v.label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: v.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
            ),
          ],
        ],
      ),
    );
  }

  /// Maps a backend refund status to its presentation.
  ///
  /// Visible for testing.
  static RefundVisuals visualsFor(String? status) {
    switch (status) {
      // The refund exists and the amount is fixed, but no money
      // moves until a human approves it.
      case 'awaiting_approval':
        return RefundVisuals(
          label: 'Awaiting approval',
          icon: Icons.pending_actions,
          foreground: Colors.indigo.shade800,
          background: Colors.indigo.shade50,
          border: Colors.indigo.shade200,
        );

      case 'rejected':
        return RefundVisuals(
          label: 'Request declined',
          icon: Icons.cancel_outlined,
          foreground: Colors.red.shade800,
          background: Colors.red.shade50,
          border: Colors.red.shade200,
        );

      case 'succeeded':
        return RefundVisuals(
          label: 'Refunded',
          icon: Icons.check_circle,
          foreground: Colors.green.shade800,
          background: Colors.green.shade50,
          border: Colors.green.shade200,
        );

      // 'failed' is retried automatically by the backend, so from
      // the customer's point of view it is still in progress.
      // Surfacing it as a failure would prompt needless support
      // contact for something already self-healing.
      case 'pending':
      case 'processing':
      case 'failed':
        return RefundVisuals(
          label: 'Processing',
          icon: Icons.hourglass_top,
          foreground: Colors.orange.shade800,
          background: Colors.orange.shade50,
          border: Colors.orange.shade200,
        );

      case 'manual':
        return RefundVisuals(
          label: 'Being processed by our team',
          icon: Icons.support_agent,
          foreground: Colors.blue.shade800,
          background: Colors.blue.shade50,
          border: Colors.blue.shade200,
        );

      case 'not_applicable':
        return RefundVisuals(
          label: 'No refund due',
          icon: Icons.info_outline,
          foreground: kLuxMuted,
          background: const Color(0xFFF5F5F5),
          border: const Color(0xFFE0E0E0),
        );

      default:
        // No refund record: an unpaid booking, or one cancelled
        // before refunds existed. Claim nothing we can't back up.
        return RefundVisuals(
          label: 'No refund recorded',
          icon: Icons.info_outline,
          foreground: kLuxMuted,
          background: const Color(0xFFF5F5F5),
          border: const Color(0xFFE0E0E0),
        );
    }
  }
}

class RefundVisuals {
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;

  const RefundVisuals({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
  });
}
