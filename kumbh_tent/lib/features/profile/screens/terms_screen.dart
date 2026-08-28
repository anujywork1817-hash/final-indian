import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _sections = [
    (
      icon: '📄',
      title: 'Acceptance of Terms',
      body:
          'By downloading and using the Kumbh Tent app, you agree to be bound by these Terms of Service. If you do not agree, please do not use our services.',
    ),
    (
      icon: '🏕️',
      title: 'Booking Policy',
      body:
          '• Bookings are confirmed only after successful payment\n'
          '• Booking confirmation and e-ticket will be sent to your registered phone number\n'
          '• Each booking is tied to a unique booking reference number\n'
          '• Check-in time is 12:00 PM and check-out time is 11:00 AM\n'
          '• Valid government-issued ID is required at check-in',
    ),
    (
      icon: '💳',
      title: 'Payment Policy',
      body:
          '• All payments are processed securely through Razorpay\n'
          '• Prices are inclusive of GST unless stated otherwise\n'
          '• Advance booking is recommended as tent availability is limited\n'
          '• Prices may vary based on surge pricing during peak Kumbh dates',
    ),
    (
      icon: '🔄',
      title: 'Cancellation & Refund Policy',
      body:
          '• Cancellations made 7+ days before check-in: 80% refund\n'
          '• Cancellations made 3-6 days before check-in: 50% refund\n'
          '• Cancellations made within 48 hours: No refund\n'
          '• Refunds are processed within 3-4 working days\n'
          '• Refunds will be credited to the original payment method',
    ),
    (
      icon: '🙋',
      title: 'Guest Responsibilities',
      body:
          '• Guests are responsible for the cleanliness and upkeep of the tent\n'
          '• Smoking and alcohol consumption is strictly prohibited\n'
          '• Loud music or noise after 10:00 PM is not permitted\n'
          '• Any damage to tent property will be charged to the guest\n'
          '• Guests must follow all camp rules and regulations',
    ),
    (
      icon: '🛎️',
      title: 'Amenities & Services',
      body:
          '• All amenities listed in the app are subject to availability\n'
          '• Daily housekeeping, power backup, and Wi-Fi are included\n'
          '• Medical support is available 24/7 on call\n'
          '• The camp management reserves the right to modify amenities',
    ),
    (
      icon: '⚠️',
      title: 'Liability',
      body:
          'Jayashri Infotech Pvt. Ltd. and the Kumbh Tent camp are not liable for:\n\n'
          '• Loss or theft of personal belongings\n'
          '• Injuries arising from personal negligence\n'
          '• Force majeure events including natural disasters or government orders\n'
          '• Changes in Kumbh 2027 schedule or government regulations',
    ),
    (
      icon: '©️',
      title: 'Intellectual Property',
      body:
          'All content in the Kumbh Tent app including logos, images, and text is the property of Jayashri Infotech Pvt. Ltd. Unauthorised use is strictly prohibited.',
    ),
    (
      icon: '⚖️',
      title: 'Governing Law',
      body:
          'These Terms of Service are governed by the laws of India. Any disputes shall be subject to the exclusive jurisdiction of courts in Nashik, Maharashtra.',
    ),
    (
      icon: '✉️',
      title: 'Contact Us',
      body:
          'For any queries regarding these Terms of Service:\n\n'
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
                    '🙏 By using this app you agree to all terms above. Jai Kumbh 2027!',
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
                  'Terms of Service',
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
              child: Text('📋', style: TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Terms of Service',
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
