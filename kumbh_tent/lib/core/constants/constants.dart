import 'package:flutter/material.dart';

// ── Luxury palette ───────────────────────────────────────
const Color kLuxDark = Color.fromARGB(255, 139, 97, 0);
const Color kLuxDark2 = Color(0xFF6E2D00);
const Color kLuxDark3 = Color(0xFF5A2400);
const Color kLuxGold = Color(0xFFC9A84C);
const Color kLuxGoldSoft = Color(0xFFF5EDD6);
const Color kLuxCream = Color(0xFFFAF7F0);
const Color kLuxMuted = Color(0xFF8A7D6B);
const Color kLuxBorder = Color(0xFFE8DCC8);

// ── TRUE Saffron Orange (new) ────────────────────────────
const Color kTrueSaffron = Color(0xFFF6720B); // main saffron orange
const Color kTrueSaffronDark = Color(
  0xFFBF4E00,
); // deeper orange — dark buttons
const Color kTrueSaffronLight = Color(0xFFFFA05A); // lighter tint — highlights
const Color kTrueSaffronPale = Color(0xFFFFF3EA); // very pale — backgrounds

// ── Aliases for legacy screens ───────────────────────────
const Color kSaffron = kLuxGold; // kept as-is — gold/amber
const Color kDeepOrange = kLuxDark; // kept as-is — dark brown
const Color kGold = kLuxGold;
const Color kCream = kLuxCream;
const Color kDark = kLuxDark;

// ── API ──────────────────────────────────────────────────
const String kBaseUrl = 'http://myapp-backend-env-1.eba-njsam29m.ap-south-1.elasticbeanstalk.com/api/v1';
// ── Storage Keys ─────────────────────────────────────────
const String kAuthToken = 'auth_token';
const String kUserPhone = 'user_phone';
const String kUserName = 'user_name';

// ── Coupon ───────────────────────────────────────────────
const String kValidCoupon = 'KUMBH10';
const double kCouponDiscount = 0.10;

// ── Tax ──────────────────────────────────────────────────
const double kGSTRate = 0.12;

// ── App Info ─────────────────────────────────────────────
const String kAppName = 'Kumbh Tent Booking';
const String kAppVersion = 'v1.0.0';
const String kAppTagline = 'Nashik Kumbh 2027';

// ── Nashik Kumbh (Simhastha) 2027 Dates ──────────────────
const List<Map<String, String>> kKumbhDates = [
  {'date': 'Apr 30', 'name': 'Akshaya Tritiya — Opening Snan', 'surge': '2x'},
  {'date': 'May 10', 'name': 'Mohini Ekadashi', 'surge': '1.5x'},
  {'date': 'May 14', 'name': 'Narasimha Jayanti', 'surge': '1.5x'},
  {
    'date': 'Jul 17',
    'name': 'Guru Purnima — First Shahi Snan 🔥',
    'surge': '3x',
  },
  {
    'date': 'Aug 7',
    'name': 'Simhastha Peak — Shravani Amavasya 🔥',
    'surge': '3.5x',
  },
  {
    'date': 'Aug 25',
    'name': 'Bhadrapada Ekadashi — Final Snan',
    'surge': '2.5x',
  },
];

// ── Tent Classes ─────────────────────────────────────────
const List<Map<String, String>> kTentClasses = [
  {'key': 'all', 'label': 'All'},
  {'key': 'regular', 'label': 'Regular'},
  {'key': 'luxury', 'label': 'Luxury'},
  {'key': 'premium', 'label': 'Premium'},
];

// ── Tent Class Colors ─────────────────────────────────────
Color kColorForClass(String cls) {
  switch (cls) {
    case 'premium':
      return const Color(0xFF7C3AED);
    case 'luxury':
      return const Color(0xFF059669);
    case 'regular':
      return const Color(0xFF0369A1);
    case 'standard':
      return const Color(0xFF0891B2);
    case 'basic':
      return const Color(0xFF0369A1);
    case 'vip':
      return const Color(0xFFD97706);
    default:
      return const Color(0xFF6B7280);
  }
}

// ── Booking Status ────────────────────────────────────────
const String kStatusConfirmed = 'confirmed';
const String kStatusPending = 'pending';
const String kStatusCompleted = 'completed';
const String kStatusCancelled = 'cancelled';

Color kStatusColor(String status) {
  switch (status) {
    case kStatusConfirmed:
      return Colors.green;
    case kStatusPending:
      return Colors.orange;
    case kStatusCancelled:
      return Colors.red;
    default:
      return Colors.grey;
  }
}

String kStatusLabel(String status) {
  switch (status) {
    case kStatusConfirmed:
      return '✅ Confirmed';
    case kStatusPending:
      return '⏳ Pending Payment';
    case kStatusCompleted:
      return '🏁 Completed';
    case kStatusCancelled:
      return '❌ Cancelled';
    default:
      return status;
  }
}

// ── Local asset images by tent class ─────────────────────
const Map<String, List<String>> kCapsuleImages = {
  'regular': [
    'assets/images/regular capsule tent.png',
    'assets/images/regular all view.png',
    'assets/images/regular inside view.png',
    'assets/images/regular inside view2.png',
    'assets/images/regular inside wiev.png',
  ],
  'luxury': [
    'assets/images/luxury Capsule tent.png',
    'assets/images/luxury all image.png',
    'assets/images/luxury inside img.png',
    'assets/images/luxury inside view.png',
    'assets/images/luxury inside view2.png',
  ],
  'premium': [
    'assets/images/premium capsule tent.png',
    'assets/images/premium all view.png',
    'assets/images/premium inside view.png',
    'assets/images/premium inside view2.png',
    'assets/images/premium .png',
  ],
};
