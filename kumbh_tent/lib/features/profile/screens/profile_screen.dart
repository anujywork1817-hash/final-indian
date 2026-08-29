import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/auth/screens/login_screen.dart';
import 'package:kumbh_tent/features/booking/screens/my_bookings_screen.dart';
import 'package:kumbh_tent/features/profile/screens/edit_profile_screen.dart';
import 'package:kumbh_tent/features/booking/screens/cancellations_screen.dart';
import 'package:kumbh_tent/features/profile/screens/wishlist_screen.dart';
import 'package:kumbh_tent/features/profile/screens/privacy_policy_screen.dart';
import 'package:kumbh_tent/features/profile/screens/terms_screen.dart';
// KYC entry point removed from Settings. kyc_screen.dart is
// intentionally left in the codebase (unreferenced) so the flow
// can be restored without rebuilding it.

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _storage = FlutterSecureStorage();
  String _phone = '';
  String _name = '';
  String _email = '';
  int _bookingCount = 0;
  int _reviewCount = 0;
  bool _loading = true;

  static const String _campPhone = '+919523415989';
  static const String _campWhatsApp = '916207803189';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final phone = await _storage.read(key: 'user_phone') ?? '';
      final profileData = await ApiService.getProfile();
      if (mounted) {
        setState(() {
          _phone = phone.isNotEmpty
              ? '+91 ${phone.replaceFirst('+91', '').trim()}'
              : '';
          _name = profileData['name']?.isNotEmpty == true
              ? profileData['name']
              : 'Guest';
          _email = profileData['email'] ?? '';
          _bookingCount = profileData['booking_count'] ?? 0;
          _reviewCount = profileData['review_count'] ?? 0;
          _loading = false;
        });
      }
    } catch (e) {
      final phone = await _storage.read(key: 'user_phone') ?? '';
      final name = await _storage.read(key: 'user_name') ?? '';
      final email = await _storage.read(key: 'user_email') ?? '';
      if (mounted) {
        setState(() {
          _phone = phone.isNotEmpty
              ? '+91 ${phone.replaceFirst('+91', '').trim()}'
              : '';
          _name = name.isNotEmpty ? name : 'Guest';
          _email = email;
          _loading = false;
        });
      }
    }
  }

  Future<void> _callCamp() async {
    final uri = Uri.parse('tel:$_campPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) _snack('Could not open dialer', AppColors.error);
    }
  }

  Future<void> _whatsappCamp() async {
    final uri = Uri.parse(
      'https://wa.me/$_campWhatsApp?text=Hi%2C%20I%20have%20a%20query%20about%20Kumbh%20Tent%20booking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) _snack('Could not open WhatsApp', AppColors.error);
    }
  }

  String get _initials {
    final trimmed = _name.trim();
    if (trimmed.isEmpty) return 'G';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: color,
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
        bottom: false,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.saffron),
              )
            : RefreshIndicator(
                onRefresh: _loadProfile,
                color: AppColors.saffron,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hello, $_name 👋',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Manage your account',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Profile summary card ────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.cardBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.07),
                              blurRadius: 18,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppColors.saffron,
                                        AppColors.goldWarm,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.saffron.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      _initials,
                                      style: GoogleFonts.poppins(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _name,
                                        style: GoogleFonts.poppins(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () {
                                          Clipboard.setData(
                                            ClipboardData(text: _phone),
                                          );
                                          _snack(
                                            'Phone number copied!',
                                            AppColors.success,
                                          );
                                        },
                                        child: Text(
                                          _phone,
                                          style: GoogleFonts.poppins(
                                            color: AppColors.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (_email.isNotEmpty)
                                        Text(
                                          _email,
                                          style: GoogleFonts.poppins(
                                            color: AppColors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(height: 1, color: AppColors.border),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _statItem('$_bookingCount', 'Bookings'),
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: AppColors.border,
                                ),
                                _statItem('$_reviewCount', 'Reviews'),
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: AppColors.border,
                                ),
                                _statItem('🪔', 'Welcome'),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Contact Us ──────────────────────────────
                      _sectionLabel('Contact Us'),
                      const SizedBox(height: 10),
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Have a question before booking?',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Our camp team is available 24/7',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _contactButton(
                                    onTap: _callCamp,
                                    icon: Icons.call_rounded,
                                    label: 'Call Us',
                                    color: AppColors.saffron,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _contactButton(
                                    onTap: _whatsappCamp,
                                    icon: Icons.chat_rounded,
                                    label: 'WhatsApp',
                                    color: const Color(0xFF25D366),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Account ─────────────────────────────────
                      _sectionLabel('Account'),
                      const SizedBox(height: 10),
                      _menuCard([
                        _menuItem(
                          Icons.person_outline,
                          'Edit Profile',
                          'Update your details',
                          () async {
                            final updated = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EditProfileScreen(),
                              ),
                            );
                            if (updated == true) _loadProfile();
                          },
                        ),
                      ]),

                      const SizedBox(height: 20),

                      // ── Bookings ────────────────────────────────
                      _sectionLabel('Bookings'),
                      const SizedBox(height: 10),
                      _menuCard([
                        _menuItem(
                          Icons.history_outlined,
                          'Booking History',
                          'View past bookings',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyBookingsScreen(),
                            ),
                          ),
                        ),
                        _menuItem(
                          Icons.qr_code_outlined,
                          'My E-Tickets',
                          'Tap a booking to view QR ticket',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyBookingsScreen(),
                            ),
                          ),
                        ),
                        _menuItem(
                          Icons.favorite_border_rounded,
                          'Wishlist',
                          'Tents you\'ve saved',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WishlistScreen(),
                            ),
                          ),
                        ),
                        _menuItem(
                          Icons.cancel_outlined,
                          'Cancellations',
                          'Refund status',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CancellationsScreen(),
                            ),
                          ),
                          last: true,
                        ),
                      ]),

                      const SizedBox(height: 20),

                      // ── Support ─────────────────────────────────
                      _sectionLabel('Support'),
                      const SizedBox(height: 10),
                      _menuCard([
                        _menuItem(
                          Icons.help_outline,
                          'Help & FAQ',
                          'Get support',
                          _callCamp,
                        ),
                        _menuItem(
                          Icons.privacy_tip_outlined,
                          'Privacy Policy',
                          '',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyScreen(),
                            ),
                          ),
                        ),
                        _menuItem(
                          Icons.description_outlined,
                          'Terms of Service',
                          '',
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TermsScreen(),
                            ),
                          ),
                          last: true,
                        ),
                      ]),

                      const SizedBox(height: 20),

                      // ── Logout ───────────────────────────────────
                      GestureDetector(
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            title: Text(
                              'Logout',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            content: Text(
                              'Are you sure you want to logout?',
                              style: GoogleFonts.poppins(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.poppins(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                ),
                                onPressed: () async {
                                  await ApiService.logout();
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const PhoneLoginScreen(),
                                      ),
                                      (route) => false,
                                    );
                                  }
                                },
                                child: Text(
                                  'Logout',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.logout_rounded,
                                color: AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Logout',
                                style: GoogleFonts.poppins(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Kumbh Tent v1.0.0 • Nashik Kumbh 2027',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(
    t,
    style: GoogleFonts.poppins(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.saffron,
      letterSpacing: 0.4,
    ),
  );

  Widget _statItem(String value, String label) => Column(
    children: [
      Text(
        value,
        style: GoogleFonts.poppins(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.poppins(color: AppColors.textMuted, fontSize: 11),
      ),
    ],
  );

  Widget _contactButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    required Color color,
  }) => Material(
    color: color.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.cardBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _menuCard(List<Widget> items) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.cardBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: items),
  );

  Widget _menuItem(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool last = false,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.softSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.saffron, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: AppColors.textMuted,
          ),
        ],
      ),
    ),
  );
}
