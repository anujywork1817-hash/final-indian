import 'package:flutter/material.dart';

/// Premium neutral + saffron/gold brand palette.
///
/// Replaces the old cream/gold-dominant palette in
/// [constants.dart] for new/redesigned screens. White is the
/// dominant surface; saffron and gold are accents only.
class AppColors {
  AppColors._();

  // ── Neutrals ─────────────────────────────────────────────
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color softSurface = Color(0xFFF8F8F8);
  static const Color border = Color(0xFFE2E2E2);
  // A touch darker than [border] — used on card outlines so
  // white cards read as distinct shapes against the white
  // background instead of relying on shadow alone.
  static const Color cardBorder = Color(0xFFE6E1DA);

  static const Color textPrimary = Color(0xFF171717);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textMuted = Color(0xFF999999);

  // ── Brand ────────────────────────────────────────────────
  static const Color saffron = Color(0xFFE85D04);
  static const Color saffronDark = Color(0xFFC2410C);
  static const Color gold = Color(0xFFC9A227);
  static const Color goldWarm = Color(0xFFD4AF37);

  static const Color black = Color(0xFF171717);
  static const Color white = Color(0xFFFFFFFF);

  // ── Status ───────────────────────────────────────────────
  static const Color success = Color(0xFF198754);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);

  // ── Class colors (tent tiers) ────────────────────────────
  static const Color classStandard = Color(0xFF0891B2);
  static const Color classLuxury = Color(0xFF059669);
  static const Color classPremium = Color(0xFF7C3AED);

  static Color forTentClass(String cls) {
    switch (cls) {
      case 'premium':
      case 'vip':
        return classPremium;
      case 'luxury':
        return classLuxury;
      default:
        return classStandard;
    }
  }
}
