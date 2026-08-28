import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = [
    (
      icon: '📱',
      title: 'Information We Collect',
      body:
          'We collect the following information when you use the Kumbh Tent app:\n\n'
          '• Mobile phone number (for OTP login)\n'
          '• Name and email address (optional, for profile)\n'
          '• Booking details including check-in/check-out dates, tent type, and number of guests\n'
          '• Payment information processed securely via Razorpay\n'
          '• Device token for push notifications (optional)',
    ),
    (
      icon: '🎯',
      title: 'How We Use Your Information',
      body:
          'Your information is used to:\n\n'
          '• Verify your identity via OTP authentication\n'
          '• Process and manage your tent bookings\n'
          '• Send booking confirmations and e-tickets\n'
          '• Send important updates about your stay\n'
          '• Improve our services and app experience',
    ),
    (
      icon: '🔐',
      title: 'Data Storage & Security',
      body:
          'Your data is stored securely on encrypted servers. We use industry-standard security measures to protect your personal information. Payment data is handled exclusively by Razorpay and is never stored on our servers.',
    ),
    (
      icon: '🤝',
      title: 'Sharing of Information',
      body:
          'We do not sell, trade, or share your personal information with third parties except:\n\n'
          '• Razorpay — for payment processing\n'
          '• Firebase — for push notifications\n'
          '• Camp management team — to manage your booking and stay\n\n'
          'All third-party services are bound by their own privacy policies.',
    ),
    (
      icon: '📞',
      title: 'OTP & Phone Number',
      body:
          'Your phone number is used solely for authentication purposes. OTPs are valid for 5 minutes and are deleted after use. We do not share your phone number with any third party.',
    ),
    (
      icon: '⚖️',
      title: 'Your Rights',
      body:
          'You have the right to:\n\n'
          '• Access your personal data\n'
          '• Update or correct your information via Edit Profile\n'
          '• Delete your account by contacting us\n'
          '• Opt out of promotional communications',
    ),
    (
      icon: '🍪',
      title: 'Cookies & Analytics',
      body:
          'The Kumbh Tent app does not use cookies. We may collect anonymised usage analytics to improve the app experience.',
    ),
    (
      icon: '🧒',
      title: "Children's Privacy",
      body:
          'Our services are not directed to children under the age of 13. We do not knowingly collect personal information from children.',
    ),
    (
      icon: '📝',
      title: 'Changes to This Policy',
      body:
          'We may update this Privacy Policy from time to time. We will notify you of any significant changes through the app. Continued use of the app after changes constitutes acceptance of the updated policy.',
    ),
    (
      icon: '✉️',
      title: 'Contact Us',
      body:
          'If you have any questions about this Privacy Policy, please contact us:\n\n'
          '📧 jayashriinfotechpvtltd@gmail.com\n\n'
          'Jayashri Infotech Pvt. Ltd.\n'
          'Nashik, Maharashtra, India',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header(context)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _sectionCard(i + 1, _sections[i]),
                  childCount: _sections.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.saffron, AppColors.saffronDark],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.saffron.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Text(
                    '🙏 Thank you for trusting Kumbh Tent for your Nashik Kumbh 2027 stay.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 20, 4),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  'Privacy Policy',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: 84,
            height: 84,
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
              child: Text('🔐', style: TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Your Privacy, Protected',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Kumbh Tent App — Nashik Kumbh 2027',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.softSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Last updated: May 2026',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionCard(
    int number,
    ({String icon, String title, String body}) section,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 16),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.softSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(section.icon, style: const TextStyle(fontSize: 19)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$number. ${section.title}',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          section.body,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.6,
          ),
        ),
      ],
    ),
  );
}
