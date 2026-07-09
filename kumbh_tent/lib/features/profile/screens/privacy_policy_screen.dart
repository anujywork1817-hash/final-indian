import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/constants/constants.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        title: Text(
          'Privacy Policy',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  const Text('🔒', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text(
                    'Privacy Policy',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: kDark,
                    ),
                  ),
                  Text(
                    'Kumbh Tent App — Nashik Kumbh 2027',
                    style: GoogleFonts.poppins(fontSize: 12, color: kLuxMuted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last updated: May 2026',
                    style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _section(
              '1. Information We Collect',
              'We collect the following information when you use the Kumbh Tent app:\n\n'
                  '• Mobile phone number (for OTP login)\n'
                  '• Name and email address (optional, for profile)\n'
                  '• Booking details including check-in/check-out dates, tent type, and number of guests\n'
                  '• Payment information processed securely via Razorpay\n'
                  '• Device token for push notifications (optional)',
            ),
            _section(
              '2. How We Use Your Information',
              'Your information is used to:\n\n'
                  '• Verify your identity via OTP authentication\n'
                  '• Process and manage your tent bookings\n'
                  '• Send booking confirmations and e-tickets\n'
                  '• Send important updates about your stay\n'
                  '• Improve our services and app experience',
            ),
            _section(
              '3. Data Storage & Security',
              'Your data is stored securely on encrypted servers. We use industry-standard security measures to protect your personal information. Payment data is handled exclusively by Razorpay and is never stored on our servers.',
            ),
            _section(
              '4. Sharing of Information',
              'We do not sell, trade, or share your personal information with third parties except:\n\n'
                  '• Razorpay — for payment processing\n'
                  '• Firebase — for push notifications\n'
                  '• Camp management team — to manage your booking and stay\n\n'
                  'All third-party services are bound by their own privacy policies.',
            ),
            _section(
              '5. OTP & Phone Number',
              'Your phone number is used solely for authentication purposes. OTPs are valid for 5 minutes and are deleted after use. We do not share your phone number with any third party.',
            ),
            _section(
              '6. Your Rights',
              'You have the right to:\n\n'
                  '• Access your personal data\n'
                  '• Update or correct your information via Edit Profile\n'
                  '• Delete your account by contacting us\n'
                  '• Opt out of promotional communications',
            ),
            _section(
              '7. Cookies & Analytics',
              'The Kumbh Tent app does not use cookies. We may collect anonymised usage analytics to improve the app experience.',
            ),
            _section(
              '8. Children\'s Privacy',
              'Our services are not directed to children under the age of 13. We do not knowingly collect personal information from children.',
            ),
            _section(
              '9. Changes to This Policy',
              'We may update this Privacy Policy from time to time. We will notify you of any significant changes through the app. Continued use of the app after changes constitutes acceptance of the updated policy.',
            ),
            _section(
              '10. Contact Us',
              'If you have any questions about this Privacy Policy, please contact us:\n\n'
                  '📧 jayashriinfotechpvtltd@gmail.com\n\n'
                  'Jayashri Infotech Pvt. Ltd.\n'
                  'Nashik, Maharashtra, India',
            ),

            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kTrueSaffron.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kTrueSaffron.withOpacity(0.3)),
              ),
              child: Text(
                '🙏 Thank you for trusting Kumbh Tent for your Nashik Kumbh 2027 stay.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: kTrueSaffronDark,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String content) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: kTrueSaffron,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kLuxGoldSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kTrueSaffron.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: kTrueSaffron.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            content,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: kLuxMuted,
              height: 1.6,
            ),
          ),
        ),
      ],
    ),
  );
}
