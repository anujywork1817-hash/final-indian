import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/home/screens/home_screen.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

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
  String? _nameError;
  String? _emailError;

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
      RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Please enter your name' : null;
      _emailError = email.isEmpty
          ? 'Email is required'
          : !_isValidEmail(email)
          ? 'Please enter a valid email'
          : null;
    });
    if (_nameError != null || _emailError != null) return;

    setState(() => _isLoading = true);
    try {
      await ApiService.updateProfile(name: name, email: email);
      await ApiService.saveNameLocally(name);
      await ApiService.saveGenderPreference(_genderPreference);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(key: homeScreenKey)),
          (r) => false,
        );
      }
    } catch (e) {
      await ApiService.saveNameLocally(name);
      await ApiService.saveGenderPreference(_genderPreference);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(key: homeScreenKey)),
          (r) => false,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ─────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.saffron, AppColors.goldWarm],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.saffron.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('🙏', style: TextStyle(fontSize: 32)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Welcome To Kumbh Tent',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '+91 ${widget.phone}',
                        style: GoogleFonts.poppins(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                Text(
                  'Complete your profile',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Used for booking confirmation & e-tickets',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Full Name ──────────────────────────────────
                _fieldLabel('Full Name'),
                const SizedBox(height: 8),
                _textField(
                  _nameController,
                  'Enter your full name',
                  Icons.person_outline,
                  TextInputType.name,
                  errorText: _nameError,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
                const SizedBox(height: 20),

                // ── Email ──────────────────────────────────────
                _fieldLabel('Email Address'),
                const SizedBox(height: 4),
                Text(
                  'For booking confirmation & e-ticket delivery',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                _textField(
                  _emailController,
                  'Enter your email',
                  Icons.email_outlined,
                  TextInputType.emailAddress,
                  errorText: _emailError,
                  onChanged: (_) {
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                  },
                ),
                const SizedBox(height: 20),

                // ── Gender ─────────────────────────────────────
                _fieldLabel('Gender Preference'),
                const SizedBox(height: 4),
                Text(
                  'For tent allocation preference',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textMuted,
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
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: sel
                                ? const LinearGradient(
                                    colors: [
                                      AppColors.saffron,
                                      AppColors.saffronDark,
                                    ],
                                  )
                                : null,
                            color: sel ? null : AppColors.softSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? AppColors.saffron
                                  : AppColors.border,
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
                                color: sel ? Colors.white : AppColors.textPrimary,
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
                PremiumButton(
                  label: 'Save & Continue',
                  icon: Icons.check_rounded,
                  verticalPadding: 16,
                  onPressed: _isLoading ? null : _saveProfile,
                ),
                const SizedBox(height: 14),

                // ── Info card ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.softSurface,
                    borderRadius: BorderRadius.circular(16),
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
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
  );

  Widget _textField(
    TextEditingController ctrl,
    String hint,
    IconData icon,
    TextInputType type, {
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final hasError = errorText != null;
    return TextField(
      controller: ctrl,
      keyboardType: type,
      onChanged: onChanged,
      textCapitalization: type == TextInputType.name
          ? TextCapitalization.words
          : TextCapitalization.none,
      style: GoogleFonts.poppins(fontSize: 15, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
        errorText: errorText,
        errorStyle: GoogleFonts.poppins(fontSize: 11, color: AppColors.error),
        prefixIcon: Icon(
          icon,
          color: hasError ? AppColors.error : AppColors.saffron,
        ),
        filled: true,
        fillColor: AppColors.softSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: hasError ? AppColors.error : AppColors.saffron,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Row(
    children: [
      Icon(icon, color: AppColors.saffron, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    ],
  );
}
