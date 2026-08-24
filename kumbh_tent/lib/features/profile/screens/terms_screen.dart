import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/constants/constants.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        title: Text(
          'Terms of Service',
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
            // ── Header ──────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  const Text('📋', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text(
                    'Terms of Service',
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
              '1. Acceptance of Terms',
              'By downloading and using the Kumbh Tent app, you agree to be bound by these Terms of Service. If you do not agree, please do not use our services.',
            ),
            _section(
              '2. Booking Policy',
              '• Bookings are confirmed only after successful payment\n'
                  '• Booking confirmation and e-ticket will be sent to your registered phone number\n'
                  '• Each booking is tied to a unique booking reference number\n'
                  '• Check-in time is 12:00 PM and check-out time is 11:00 AM\n'
                  '• Valid government-issued ID is required at check-in',
            ),
            _section(
              '3. Payment Policy',
              '• All payments are processed securely through Razorpay\n'
                  '• Prices are inclusive of GST unless stated otherwise\n'
                  '• Advance booking is recommended as tent availability is limited\n'
                  '• Prices may vary based on surge pricing during peak Kumbh dates',
            ),
            _section(
              '4. Cancellation & Refund Policy',
              '• Cancellations made 7+ days before check-in: 80% refund\n'
                  '• Cancellations made 3-6 days before check-in: 50% refund\n'
                  '• Cancellations made within 48 hours: No refund\n'
                  '• Refunds are processed within 3-4 working days\n'
                  '• Refunds will be credited to the original payment method',
            ),
            _section(
              '5. Guest Responsibilities',
              '• Guests are responsible for the cleanliness and upkeep of the tent\n'
                  '• Smoking and alcohol consumption is strictly prohibited\n'
                  '• Loud music or noise after 10:00 PM is not permitted\n'
                  '• Any damage to tent property will be charged to the guest\n'
                  '• Guests must follow all camp rules and regulations',
            ),
            _section(
              '6. Amenities & Services',
              '• All amenities listed in the app are subject to availability\n'
                  '• Daily housekeeping, power backup, and Wi-Fi are included\n'
                  '• Medical support is available 24/7 on call\n'
                  '• The camp management reserves the right to modify amenities',
            ),
            _section(
              '7. Liability',
              'Jayashri Infotech Pvt. Ltd. and the Kumbh Tent camp are not liable for:\n\n'
                  '• Loss or theft of personal belongings\n'
                  '• Injuries arising from personal negligence\n'
                  '• Force majeure events including natural disasters or government orders\n'
                  '• Changes in Kumbh 2027 schedule or government regulations',
            ),
            _section(
              '8. Intellectual Property',
              'All content in the Kumbh Tent app including logos, images, and text is the property of Jayashri Infotech Pvt. Ltd. Unauthorised use is strictly prohibited.',
            ),
            _section(
              '9. Governing Law',
              'These Terms of Service are governed by the laws of India. Any disputes shall be subject to the exclusive jurisdiction of courts in Nashik, Maharashtra.',
            ),
            _section(
              '10. Contact Us',
              'For any queries regarding these Terms of Service:\n\n'
                  '📧 jayashriinfotechpvtltd@gmail.com\n\n'
                  'Jayashri Infotech Pvt. Ltd.\n'
                  'Nashik, Maharashtra, India',
            ),

            const SizedBox(height: 32),

            // ── Footer banner ────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kTrueSaffron.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kTrueSaffron.withOpacity(0.3)),
              ),
              child: Text(
                '🙏 By using this app you agree to all terms above. Jai Kumbh 2027!',
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
