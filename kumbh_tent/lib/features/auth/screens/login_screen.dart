import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/features/auth/screens/otp_screen.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';
import 'package:kumbh_tent/shared/widgets/premium_badge.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _phoneError;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero ───────────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.saffron, AppColors.goldWarm],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.saffron.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.holiday_village_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome to Kumbh Tent',
                          style: GoogleFonts.poppins(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'NASHIK KUMBH 2027',
                          style: GoogleFonts.poppins(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    'Enter your phone number',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'We\'ll send a 6-digit OTP to verify your number',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Phone input ───────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.softSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _phoneError != null
                            ? AppColors.error
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: Text(
                            '+91',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.saffron,
                            ),
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          color: AppColors.border,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) {
                              if (_phoneError != null) {
                                setState(() => _phoneError = null);
                              }
                            },
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                              letterSpacing: 2,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: 'Mobile number',
                              hintStyle: GoogleFonts.poppins(
                                color: AppColors.textMuted,
                                letterSpacing: 1,
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_phoneError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        _phoneError!,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // ── Send OTP button ───────────────────────
                  PremiumButton(
                    label: 'Send OTP',
                    icon: Icons.arrow_forward_rounded,
                    verticalPadding: 16,
                    onPressed: _isLoading ? null : _sendOTP,
                  ),

                  const SizedBox(height: 28),

                  // ── Key dates card ────────────────────────
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.saffron.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.event_note_rounded,
                                size: 15,
                                color: AppColors.saffron,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'KUMBH 2027 — KEY DATES',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // BUG-10: single source of truth — the festival
                        // calendar lives in constants.dart (kKumbhDates),
                        // shared with the search screen, instead of a
                        // second hardcoded copy that could drift.
                        for (var i = 0; i < kKumbhDates.length; i++) ...[
                          if (i > 0) _divider(),
                          _dateRow(
                            kKumbhDates[i]['date']!,
                            kKumbhDates[i]['name']!,
                            isPeak: kKumbhDates[i]['name']!.contains('🔥'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, color: AppColors.border);

  Widget _dateRow(String date, String name, {bool isPeak = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              date,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.saffronDark,
              ),
            ),
          ),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: isPeak ? AppColors.textPrimary : AppColors.textMuted,
                fontWeight: isPeak ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (isPeak)
            const PremiumBadge(label: 'PEAK', style: PremiumBadgeStyle.gold),
        ],
      ),
    );
  }

  void _sendOTP() async {
    if (_phoneController.text.length != 10) {
      setState(() => _phoneError = 'Enter a valid 10-digit number');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ApiService.sendOTP(_phoneController.text);
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'OTP sent to ${_phoneController.text}',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: AppColors.saffronDark,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OTPScreen(phone: _phoneController.text),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}
