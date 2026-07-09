import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/features/home/screens/home_screen.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/features/auth/screens/name_setup_screen.dart';

class OTPScreen extends StatefulWidget {
  final String phone;
  const OTPScreen({super.key, required this.phone});

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
  int _resendSeconds = 10;
  Timer? _timer;

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
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeCtrl.dispose();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 10);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendSeconds > 0)
          _resendSeconds--;
        else
          t.cancel();
      });
    });
  }

  Future<void> _resendOTP() async {
    setState(() => _isResending = true);
    try {
      final res = await ApiService.sendOTP(widget.phone);
      if (mounted) {
        _snack('OTP: ${res['otp']}', kTrueSaffronDark);
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
        _startTimer();
      }
    } catch (e) {
      if (mounted) _snack('Failed to resend OTP', Colors.red.shade900);
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
      backgroundColor: kTrueSaffronPale,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────
            Container(
              height: 240,
              width: double.infinity,
              color: kTrueSaffron,
              child: SafeArea(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kTrueSaffronDark,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.phone_android_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Verify OTP',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sent to +91 ${widget.phone}',
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Body ───────────────────────────────────────────
            FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Enter code',
                      style: GoogleFonts.poppins(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: kDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '6-digit code sent to your number',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: kLuxMuted,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── OTP boxes ─────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (i) => _otpBox(i)),
                    ),
                    const SizedBox(height: 32),

                    // ── Verify button ─────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kTrueSaffron,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isLoading ? null : _verifyOTP,
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Verify & Continue',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Resend ────────────────────────────────────
                    Center(
                      child: _isResending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: kTrueSaffron,
                                strokeWidth: 2,
                              ),
                            )
                          : _resendSeconds > 0
                          ? RichText(
                              text: TextSpan(
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: kLuxMuted,
                                ),
                                children: [
                                  const TextSpan(text: 'Resend code in '),
                                  TextSpan(
                                    text: '${_resendSeconds}s',
                                    style: const TextStyle(
                                      color: kTrueSaffron,
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
                                  color: kTrueSaffron,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // ── Change number ─────────────────────────────
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(foregroundColor: kLuxMuted),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.arrow_back_ios,
                              size: 12,
                              color: kLuxMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Change number',
                              style: GoogleFonts.poppins(
                                color: kLuxMuted,
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
          ],
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
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          color: Colors.black,
          fontFamily: 'monospace',
          height: 1.0,
        ),
        cursorColor: kTrueSaffron,
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: filled ? kTrueSaffron.withOpacity(0.1) : kLuxGoldSoft,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: kLuxBorder, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kTrueSaffron, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: filled ? kTrueSaffron : kLuxBorder,
              width: filled ? 1.5 : 0.8,
            ),
          ),
        ),
        onChanged: (val) {
          if (val.isNotEmpty && index < 5)
            _focusNodes[index + 1].requestFocus();
          if (val.isEmpty && index > 0) _focusNodes[index - 1].requestFocus();
          setState(() {});
        },
      ),
    );
  }

  void _verifyOTP() async {
    if (_otp.length != 6) {
      _snack('Enter all 6 digits', kTrueSaffronDark);
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
      _snack('Invalid OTP. Try again.', Colors.red.shade900);
    }
  }
}
