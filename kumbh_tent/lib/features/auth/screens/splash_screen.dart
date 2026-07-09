import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kumbh_tent/features/auth/screens/login_screen.dart';
import 'package:kumbh_tent/features/home/screens/home_screen.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _ringController;
  late AnimationController _fadeController;

  late Animation<double> _ringAnim;
  late Animation<double> _fadeAnim;

  static const _storage = FlutterSecureStorage();

  // ── Saffron Orange theme ──────────────────────────────────
  static const _cream = kLuxCream; // #FAF7F0

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _ringAnim = CurvedAnimation(parent: _ringController, curve: Curves.easeOut);
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _ringController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fadeController.forward();
    });
    Future.delayed(const Duration(milliseconds: 2800), _navigate);
  }

  Future<void> _navigate() async {
    final token = await _storage.read(key: 'auth_token');
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            token != null ? HomeScreen() : PhoneLoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _ringController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB45309), Color(0xFFD97706)],
          ),
        ),
        child: Stack(
          children: [
            // Background ring
            Center(
              child: AnimatedBuilder(
                animation: _ringAnim,
                builder: (_, __) => Stack(
                  alignment: Alignment.center,
                  children: [
                    _ring(320, (0.06 * _ringAnim.value * 255).round()),
                  ],
                ),
              ),
            ),

            // Main Content
            FadeTransition(
              opacity: _fadeAnim,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '✦ WELCOME TO NASHIK KUMBH TENT ✦',
                      style: GoogleFonts.cinzel(
                        fontSize: 11,
                        color: _cream.withAlpha(160),
                        letterSpacing: 2,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // Logo
                    Container(
                      width: 210,
                      height: 210,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.06),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.15),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.asset(
                          'assets/logo/kumbh_logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Title
                    Text(
                      'KUMBH',
                      style: GoogleFonts.cinzel(
                        fontSize: 46,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: _cream,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      'LUXURY PILGRIMAGE STAYS',
                      style: TextStyle(
                        fontSize: 11,
                        color: _cream.withAlpha(180),
                        letterSpacing: 5,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Ornament
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 1,
                          color: _cream.withAlpha(100),
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '✦',
                            style: TextStyle(color: _cream, fontSize: 14),
                          ),
                        ),

                        Container(
                          width: 40,
                          height: 1,
                          color: _cream.withAlpha(100),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Event text
                    Text(
                      'SIMHASTHA NASHIK 2027',
                      style: TextStyle(
                        fontSize: 12,
                        color: _cream.withAlpha(200),
                        letterSpacing: 3,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Small tagline
                    Text(
                      'Premium Capsule Tent Experience',
                      style: TextStyle(
                        fontSize: 10,
                        color: _cream.withAlpha(140),
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Loader
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(_cream),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Indicator
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 120,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _cream.withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ring(double size, int alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _cream.withAlpha(alpha), width: 1),
      ),
    );
  }
}
