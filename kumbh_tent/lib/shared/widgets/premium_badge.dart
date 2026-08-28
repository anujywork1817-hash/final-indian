import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';

enum PremiumBadgeStyle { dark, saffron, gold, success, danger }

/// Small pill badge used for LUXURY / PREMIUM / SOLD OUT / etc.
class PremiumBadge extends StatelessWidget {
  final String label;
  final PremiumBadgeStyle style;
  final IconData? icon;

  const PremiumBadge({
    super.key,
    required this.label,
    this.style = PremiumBadgeStyle.dark,
    this.icon,
  });

  Color get _bg {
    switch (style) {
      case PremiumBadgeStyle.saffron:
        return AppColors.saffron;
      case PremiumBadgeStyle.gold:
        return AppColors.goldWarm;
      case PremiumBadgeStyle.success:
        return AppColors.success;
      case PremiumBadgeStyle.danger:
        return AppColors.error;
      case PremiumBadgeStyle.dark:
        return Colors.black.withValues(alpha: 0.65);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 11),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
