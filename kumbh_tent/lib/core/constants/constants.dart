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

// Must stay in sync with ApiService.baseUrl in
// lib/core/network/api_service.dart — some screens call the API
// through Dio via ApiService, others use the raw http package
// with this constant, so both have to point at the same backend.
//
// SERVER — kumbh_backend deployed at ~/kumbh_tent_backend on
// 192.168.1.222 (Docker Compose, gateway on 18090). Reachable
// from any device on the same LAN; the phone does NOT need the
// adb USB tunnel for this address, only for the localhost one
// below.
//
// THE PORT IS REQUIRED. Without it the URL means port 80, where
// nothing is listening (it 404s), so every call fails and the
// screens fall back to whatever they last held — which looks
// like "the filter does nothing" rather than "the app is
// offline".
//
// This is a private LAN IP, so it only works for devices on the
// same network — for access from outside, that server needs a
// domain + reverse proxy (see the deployment notes) and this
// should be swapped to that URL instead.
const String kBaseUrl = 'http://bharat-tent-api-alb.eba-32svn3rz.ap-south-1.elasticbeanstalk.com/api/v1';

// Local Docker Compose on this PC — plain http, not https: the
// local gateway serves no TLS. localhost works because the phone
// reaches the PC through an adb USB tunnel, which `flutter run`
// clears on every attach; keep it alive with
// kumbh_tent/keep-tunnel.ps1.
//const String kBaseUrl = 'http://localhost:18090/api/v1';
//   physical device over Wi-Fi -> http://192.168.1.40:18090/api/v1
//   Android emulator           -> http://10.0.2.2:18090/api/v1

// Production / staging — swap in as needed.
//const String kBaseUrl = 'https://d3dmb495g7jwhi.cloudfront.net/api/v1';
//const String kBaseUrl = 'http://myapp-backend-env-1.eba-njsam29m.ap-south-1.elasticbeanstalk.com/api/v1';

// ── Storage Keys ─────────────────────────────────────────
const String kAuthToken = 'auth_token';
const String kUserPhone = 'user_phone';
const String kUserName = 'user_name';

// ── Coupon ───────────────────────────────────────────────
const String kValidCoupon = 'KUMBH10';
const double kCouponDiscount = 0.10;

// ── Tax ──────────────────────────────────────────────────
//
// GST on tent accommodation follows the hotel-tariff slabs: 12%
// (6% CGST + 6% SGST) for a taxable amount up to ₹7,500, 18% (9% +
// 9%) above that. Must stay in sync with the same threshold in
// kumbh_backend/booking-service/handler.go.
const double kGSTThreshold = 7500;
const double kGSTRateLow = 0.12;
const double kGSTRateHigh = 0.18;

double gstRateFor(double taxableAmount) =>
    taxableAmount > kGSTThreshold ? kGSTRateHigh : kGSTRateLow;

// ── App Info ─────────────────────────────────────────────
const String kAppName = 'Bharat Tent Booking';
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
//
// `key` is sent to the API as ?class=, so it must be a value the
// backend actually stores in tents.class — basic, standard,
// premium, luxury or vip. `label` is the display text and may
// differ. This list used the key 'regular', which is a label and
// matches no tent, so selecting it could only ever return an
// empty list. Pinned by test/tent_class_images_test.dart.
const List<Map<String, String>> kTentClasses = [
  {'key': 'all', 'label': 'All'},
  {'key': 'standard', 'label': 'Regular'},
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
//
// Keys MUST cover every class the backend can return —
// basic, standard, premium, luxury, vip. They previously did
// not: the map was keyed on 'regular', which is a UI label, not
// a value the API ever sends. Any tent whose class had no entry
// fell through to a fallback that was itself missing, and the
// resulting null-assertion crash aborted the whole tent list.
const List<String> _regularImages = [
  'assets/images/regular capsule tent.png',
  'assets/images/regular all view.png',
  'assets/images/regular inside view.png',
  'assets/images/regular inside view2.png',
  'assets/images/regular inside wiev.png',
];

const Map<String, List<String>> kCapsuleImages = {
  // 'basic' and 'standard' share the regular artwork; there is
  // no separate asset set for them.
  'basic': _regularImages,
  'standard': _regularImages,
  'regular': _regularImages,
  'luxury': [
    'assets/images/luxury Capsule tent.png',
    'assets/images/luxury all image.png',
    'assets/images/luxury inside img.png',
    'assets/images/luxury inside view.png',
    'assets/images/luxury inside view2.png',
  ],
  'premium': _premiumImages,
  // VIP has no dedicated artwork; premium is the closest match.
  'vip': _premiumImages,
};

const List<String> _premiumImages = [
  'assets/images/premium capsule tent.png',
  'assets/images/premium all view.png',
  'assets/images/premium inside view.png',
  'assets/images/premium inside view2.png',
  'assets/images/premium .png',
];

/// Images for a tent class, never null and never throwing.
///
/// Callers previously wrote `kCapsuleImages[cls] ?? kCapsuleImages['standard']!`
/// — but 'standard' was not a key, so the fallback itself was
/// null and the `!` threw. Use this instead.
List<String> imagesForClass(String? tentClass) =>
    kCapsuleImages[tentClass] ?? _regularImages;
