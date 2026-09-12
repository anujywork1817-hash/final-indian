import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/features/home/screens/home_screen.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/auth/screens/name_setup_screen.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

class OTPScreen extends StatefulWidget {
  final String phone;
  // No SMS provider is wired up yet — when the server has
  // OTP_DEBUG=true it echoes the code back in the send-otp response,
  // and login_screen passes it through here so it's visible on
  // screen for manual testing. Null once a real SMS provider exists
  // (or OTP_DEBUG is off), and this whole banner/autofill disappears.
  final String? debugOtp;
  const OTPScreen({super.key, required this.phone, this.debugOtp});

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _isResending = false;
  int _resendSeconds = 30;
  Timer? _timer;
  String? _debugOtp;

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
    _startTimer();
    _applyDebugOtp(widget.debugOtp);
  }

  void _applyDebugOtp(String? otp) {
    _debugOtp = otp;
    if (otp != null && otp.length == 6) {
      for (var i = 0; i < 6; i++) {
        _controllers[i].text = otp[i];
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeCtrl.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0) {
          _resendSeconds--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _resendOTP() async {
    setState(() => _isResending = true);
    try {
      final res = await ApiService.sendOTP(widget.phone);
      if (mounted) {
        final debugOtp = res['otp'] as String?;
        _snack(
          debugOtp != null
              ? 'OTP sent to ${widget.phone}: $debugOtp'
              : 'OTP sent to ${widget.phone}',
          AppColors.saffronDark,
        );
        for (final c in _controllers) {
          c.clear();
        }
        setState(() => _applyDebugOtp(debugOtp));
        _focusNodes[0].requestFocus();
        _startTimer();
      }
    } catch (e) {
      if (mounted) _snack('Failed to resend OTP', AppColors.error);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            Icons.phone_android_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Verify OTP',
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sent to +91 ${widget.phone}',
                          style: GoogleFonts.poppins(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        if (_debugOtp != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.saffron.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.saffron.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ),
                            child: Text(
                              'TEST MODE — OTP: $_debugOtp',
                              style: GoogleFonts.poppins(
                                color: AppColors.saffronDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    'Enter code',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '6-digit code sent to your number',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── OTP boxes ─────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (i) => _otpBox(i)),
                  ),
                  const SizedBox(height: 28),

                  // ── Verify button ─────────────────────────────
                  PremiumButton(
                    label: 'Verify & Continue',
                    icon: Icons.check_rounded,
                    verticalPadding: 16,
                    onPressed: _isLoading ? null : _verifyOTP,
                  ),
                  const SizedBox(height: 24),

                  // ── Resend ────────────────────────────────────
                  Center(
                    child: _isResending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: AppColors.saffron,
                              strokeWidth: 2,
                            ),
                          )
                        : _resendSeconds > 0
                        ? RichText(
                            text: TextSpan(
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                              children: [
                                const TextSpan(text: 'Resend code in '),
                                TextSpan(
                                  text: '${_resendSeconds}s',
                                  style: const TextStyle(
                                    color: AppColors.saffron,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GestureDetector(
                            onTap: _resendOTP,
                            child: Text(
                              'Resend OTP',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: AppColors.saffron,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),

                  // ── Change number ─────────────────────────────
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.arrow_back_ios_rounded,
                            size: 12,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Change number',
                            style: GoogleFonts.poppins(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
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

  Widget _otpBox(int index) {
    final filled = _controllers[index].text.isNotEmpty;
    return SizedBox(
      width: 46,
      height: 58,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: GoogleFonts.poppins(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          height: 1.0,
        ),
        cursorColor: AppColors.saffron,
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: filled
              ? AppColors.saffron.withValues(alpha: 0.08)
              : AppColors.softSurface,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.saffron, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: filled ? AppColors.saffron : AppColors.border,
              width: filled ? 1.5 : 1,
            ),
          ),
        ),
        onChanged: (val) {
          if (val.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          }
          if (val.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
          setState(() {});
        },
      ),
    );
  }

  void _verifyOTP() async {
    if (_otp.length != 6) {
      _snack('Enter all 6 digits', AppColors.saffronDark);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ApiService.verifyOTP(widget.phone, _otp);
      setState(() => _isLoading = false);
      final name = await ApiService.getStoredName();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => (name == null || name.isEmpty)
                ? NameSetupScreen(phone: widget.phone)
                : const HomeScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _snack('Invalid OTP. Try again.', AppColors.error);
    }
  }
}
