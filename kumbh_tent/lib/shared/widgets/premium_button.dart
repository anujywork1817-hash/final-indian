import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';

/// Gradient CTA button with a subtle press-scale animation —
/// used for primary actions that should stand out more than the
/// theme's flat [ElevatedButton] (booking CTAs, empty-state
/// actions, etc).
class PremiumButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;
  final double verticalPadding;

  const PremiumButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.outlined = false,
    this.verticalPadding = 14,
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> {
  double _scale = 1;

  void _setScale(double v) {
    if (widget.onPressed == null) return;
    setState(() => _scale = v);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    return GestureDetector(
      onTapDown: (_) => _setScale(0.97),
      onTapUp: (_) => _setScale(1),
      onTapCancel: () => _setScale(1),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: widget.verticalPadding),
          decoration: BoxDecoration(
            gradient: disabled
                ? null
                : LinearGradient(
                    colors: widget.outlined
                        ? [Colors.white, Colors.white]
                        : [AppColors.saffron, AppColors.saffronDark],
                  ),
            color: disabled
                ? AppColors.textMuted.withValues(alpha: 0.3)
                : (widget.outlined ? Colors.white : null),
            borderRadius: BorderRadius.circular(14),
            border: widget.outlined
                ? Border.all(color: AppColors.saffron.withValues(alpha: 0.4))
                : null,
            boxShadow: disabled || widget.outlined
                ? null
                : [
                    BoxShadow(
                      color: AppColors.saffron.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 17,
                  color: widget.outlined ? AppColors.saffron : Colors.white,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: widget.outlined ? AppColors.saffron : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
