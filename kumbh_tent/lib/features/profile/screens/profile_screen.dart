import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/features/auth/screens/login_screen.dart';
import 'package:kumbh_tent/features/booking/screens/my_bookings_screen.dart';
import 'package:kumbh_tent/features/profile/screens/edit_profile_screen.dart';
import 'package:kumbh_tent/features/booking/screens/cancellations_screen.dart';
import 'package:kumbh_tent/features/profile/screens/privacy_policy_screen.dart';
import 'package:kumbh_tent/features/profile/screens/terms_screen.dart';
import 'package:kumbh_tent/features/profile/screens/kyc_screen.dart';

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
              : 'User $_phone';
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
          _name = name.isNotEmpty ? name : 'User $_phone';
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
      if (mounted) _snack('Could not open dialer', Colors.red);
    }
  }

  Future<void> _whatsappCamp() async {
    final uri = Uri.parse(
      'https://wa.me/$_campWhatsApp?text=Hi%2C%20I%20have%20a%20query%20about%20Kumbh%20Tent%20booking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) _snack('Could not open WhatsApp', Colors.red);
    }
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
      backgroundColor: kTrueSaffronPale,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kTrueSaffron))
          : RefreshIndicator(
              onRefresh: _loadProfile,
              color: kTrueSaffron,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // ── Header ─────────────────────────────────────
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [kTrueSaffronDark, kTrueSaffron],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(40),
                          bottomRight: Radius.circular(40),
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
                          child: Column(
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.6),
                                    width: 3,
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    '🙏',
                                    style: TextStyle(fontSize: 36),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _name,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(text: _phone),
                                  );
                                  _snack('Phone number copied!', Colors.green);
                                },
                                child: Text(
                                  _phone,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (_email.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.email_outlined,
                                        color: Colors.white60,
                                        size: 13,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _email,
                                        style: GoogleFonts.poppins(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _statItem('$_bookingCount', 'Bookings'),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: Colors.white30,
                                  ),
                                  _statItem('$_reviewCount', 'Reviews'),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: Colors.white30,
                                  ),
                                  _statItem('🪔', 'Welcome'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Contact Us ──────────────────────────────
                          _sectionLabel('Contact Us'),
                          const SizedBox(height: 8),
                          _card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Have a question before booking?',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: kDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Our camp team is available 24/7',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: kLuxMuted,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _callCamp,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kTrueSaffron,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.call,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Call Us',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: _whatsappCamp,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF25D366),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.chat,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'WhatsApp',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
                          const SizedBox(height: 8),
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
                            _menuItem(
                              Icons.verified_outlined,
                              'KYC Verification',
                              'Verify your identity',
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      KYCScreen(currentStatus: 'not_submitted'),
                                ),
                              ),
                            ),
                            _menuItem(
                              Icons.language_outlined,
                              'Language',
                              'Hindi / English',
                              () {},
                            ),
                          ]),

                          const SizedBox(height: 20),

                          // ── Bookings ────────────────────────────────
                          _sectionLabel('Bookings'),
                          const SizedBox(height: 8),
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
                              Icons.cancel_outlined,
                              'Cancellations',
                              'Refund status',
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CancellationsScreen(),
                                ),
                              ),
                            ),
                          ]),

                          const SizedBox(height: 20),

                          // ── Support ─────────────────────────────────
                          _sectionLabel('Support'),
                          const SizedBox(height: 8),
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
                            ),
                          ]),

                          const SizedBox(height: 20),

                          // ── Logout ───────────────────────────────────
                          GestureDetector(
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: kLuxGoldSoft,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                title: Text(
                                  'Logout',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    color: kDark,
                                  ),
                                ),
                                content: Text(
                                  'Are you sure you want to logout?',
                                  style: GoogleFonts.poppins(color: kLuxMuted),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.poppins(
                                        color: kLuxMuted,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
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
                                color: Colors.red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.logout_rounded,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Logout',
                                    style: GoogleFonts.poppins(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'Kumbh Tent v1.0.0 • Nashik Kumbh 2027',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: kLuxMuted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionLabel(String t) => Text(
    t,
    style: GoogleFonts.poppins(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: kTrueSaffron,
      letterSpacing: 0.5,
    ),
  );

  Widget _statItem(String value, String label) => Column(
    children: [
      Text(
        value,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
      ),
    ],
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: kLuxGoldSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
      boxShadow: [
        BoxShadow(
          color: kTrueSaffron.withOpacity(0.06),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _menuCard(List<Widget> items) => Container(
    decoration: BoxDecoration(
      color: kLuxGoldSoft,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
      boxShadow: [
        BoxShadow(
          color: kTrueSaffron.withOpacity(0.06),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(children: items),
  );

  Widget _menuItem(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: kTrueSaffron.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kTrueSaffron.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kTrueSaffron, size: 18),
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
                    color: kDark,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
                  ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 14, color: kLuxMuted),
        ],
      ),
    ),
  );
}
