import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/features/home/screens/home_screen.dart';

class NameSetupScreen extends StatefulWidget {
  final String phone;
  const NameSetupScreen({super.key, required this.phone});

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String _genderPreference = 'Other';

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (name.isEmpty) {
      _snack('Please enter your name');
      return;
    }
    if (email.isNotEmpty && !_isValidEmail(email)) {
      _snack('Please enter a valid email');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await ApiService.updateProfile(
        name: name,
        email: email.isEmpty ? null : email,
      );
      await ApiService.saveNameLocally(name);
      await ApiService.saveGenderPreference(_genderPreference);
      if (mounted)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (r) => false,
        );
    } catch (e) {
      await ApiService.saveNameLocally(name);
      await ApiService.saveGenderPreference(_genderPreference);
      if (mounted)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (r) => false,
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _skipProfile() async {
    final defaultName =
        'Pilgrim ${widget.phone.substring(widget.phone.length - 4)}';
    await ApiService.saveNameLocally(defaultName);
    await ApiService.saveGenderPreference('Other');
    if (mounted)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (r) => false,
      );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: kTrueSaffronDark,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Header ─────────────────────────────────────────
              Container(
                height: 240,
                width: double.infinity,
                color: kTrueSaffron,
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kTrueSaffronDark,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                            width: 1,
                          ),
                        ),
                        child: const Center(
                          child: Text('🙏', style: TextStyle(fontSize: 32)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Welcome To Kumbh Tent',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '+91 ${widget.phone}',
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Body ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete your profile',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: kDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Used for booking confirmation & e-tickets',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: kLuxMuted,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Full Name ──────────────────────────────────
                    _fieldLabel('Full Name *'),
                    const SizedBox(height: 8),
                    _textField(
                      _nameController,
                      'Enter your full name',
                      Icons.person_outline,
                      TextInputType.name,
                    ),
                    const SizedBox(height: 20),

                    // ── Email ──────────────────────────────────────
                    _fieldLabel('Email Address'),
                    const SizedBox(height: 4),
                    Text(
                      'For booking confirmation & e-ticket delivery',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: kLuxMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _textField(
                      _emailController,
                      'Enter your email (optional)',
                      Icons.email_outlined,
                      TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),

                    // ── Gender ─────────────────────────────────────
                    _fieldLabel('Gender Preference'),
                    const SizedBox(height: 4),
                    Text(
                      'For tent allocation preference',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: kLuxMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['Male', 'Female', 'Other'].map((gender) {
                        final sel = _genderPreference == gender;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _genderPreference = gender),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: sel ? kTrueSaffron : kLuxGoldSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sel
                                      ? kTrueSaffronDark
                                      : kTrueSaffron.withOpacity(0.25),
                                  width: sel ? 1.5 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  gender == 'Male'
                                      ? '👨 Male'
                                      : gender == 'Female'
                                      ? '👩 Female'
                                      : '🌐 Other',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : kDark,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),

                    // ── Save button ────────────────────────────────
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
                        onPressed: _isLoading ? null : _saveProfile,
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
                                'Save & Continue 🪔',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Skip button ────────────────────────────────
                    Center(
                      child: TextButton(
                        onPressed: _skipProfile,
                        child: Text(
                          'Skip for now',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: kLuxMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── Info card ──────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: kLuxGoldSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: kTrueSaffron.withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          _infoRow(
                            Icons.person_outline,
                            'Name appears on your E-Ticket & booking',
                          ),
                          const SizedBox(height: 8),
                          _infoRow(
                            Icons.email_outlined,
                            'Email used for booking confirmation & reminders',
                          ),
                          const SizedBox(height: 8),
                          _infoRow(
                            Icons.wc_outlined,
                            'Gender preference used for tent allocation',
                          ),
                          const SizedBox(height: 8),
                          _infoRow(
                            Icons.lock_outline,
                            'Your data is safe and never shared',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: kTrueSaffron,
    ),
  );

  Widget _textField(
    TextEditingController ctrl,
    String hint,
    IconData icon,
    TextInputType type,
  ) => TextField(
    controller: ctrl,
    keyboardType: type,
    textCapitalization: type == TextInputType.name
        ? TextCapitalization.words
        : TextCapitalization.none,
    style: GoogleFonts.poppins(fontSize: 15, color: kDark),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: kLuxMuted, fontSize: 14),
      prefixIcon: Icon(icon, color: kTrueSaffron),
      filled: true,
      fillColor: kLuxGoldSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kTrueSaffron.withOpacity(0.25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kTrueSaffron.withOpacity(0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kTrueSaffron, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );

  Widget _infoRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: kTrueSaffron, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: GoogleFonts.poppins(fontSize: 11, color: kDark),
        ),
      ),
    ],
  );
}
