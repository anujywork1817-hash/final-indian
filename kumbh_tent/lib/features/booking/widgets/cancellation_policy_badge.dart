import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/constants/constants.dart';

/// Colored badge showing a tent's cancellation policy tier.
///
/// Reads the policy fields the backend now returns on every tent
/// (`cancellation_policy_type`, `free_cancellation_hours`, etc —
/// see kumbh_backend/migrations/002_cancellation_policy.sql).
/// This widget only ever DISPLAYS what the server sent; it never
/// computes a refund amount itself.
class CancellationPolicyBadge extends StatelessWidget {
  final Map<String, dynamic> tent;
  const CancellationPolicyBadge({super.key, required this.tent});

  @override
  Widget build(BuildContext context) {
    final v = visualsFor(tent);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: v.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: v.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: v.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  v.explanation,
                  style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Visible for testing/reuse — maps a tent's policy fields to
  /// the tier badge shown on the tent-detail and booking screens.
  static PolicyBadgeVisuals visualsFor(Map<String, dynamic> tent) {
    final type = (tent['cancellation_policy_type'] as String?) ?? 'FREE_CANCELLATION';
    final freeHours = (tent['free_cancellation_hours'] as num?)?.toInt() ?? 168;
    final penaltyPct = (tent['partial_refund_penalty_percent'] as num?)?.toDouble() ?? 30;
    final freeDays = (freeHours / 24).round();

    if (type == 'NON_REFUNDABLE') {
      return PolicyBadgeVisuals(
        emoji: '🔴',
        title: 'Non-Refundable',
        explanation: 'This booking cannot be refunded once confirmed.',
        foreground: Colors.red.shade800,
        background: Colors.red.shade50,
        border: Colors.red.shade200,
      );
    }

    // Every other configured type runs the same time-based ladder
    // using this tent's windows — the badge shows the most
    // generous tier (free cancellation), since that's what a
    // guest booking right now would get if they cancel promptly.
    return PolicyBadgeVisuals(
      emoji: '🟢',
      title: 'Free Cancellation',
      explanation: freeDays > 0
          ? 'Free up to $freeDays day${freeDays == 1 ? '' : 's'} before check-in, '
              'then a ${penaltyPct.toStringAsFixed(0)}% fee applies.'
          : 'Free cancellation window applies — see booking summary for the exact deadline.',
      foreground: Colors.green.shade800,
      background: Colors.green.shade50,
      border: Colors.green.shade200,
    );
  }
}

class PolicyBadgeVisuals {
  final String emoji;
  final String title;
  final String explanation;
  final Color foreground;
  final Color background;
  final Color border;

  const PolicyBadgeVisuals({
    required this.emoji,
    required this.title,
    required this.explanation,
    required this.foreground,
    required this.background,
    required this.border,
  });
}
