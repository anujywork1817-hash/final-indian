import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'https://kumbh-gateway.onrender.com/api/v1';

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  static const _storage = FlutterSecureStorage();

  static Future<void> setAuthHeader() async {
    final token = await _storage.read(key: 'auth_token');
    final phone = await _storage.read(key: 'user_phone');
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
    if (phone != null) {
      _dio.options.headers['X-User-Phone'] = phone;
    }
  }

  static Future<String?> getStoredPhone() async {
    return await _storage.read(key: 'user_phone');
  }

  static Future<String?> getStoredName() async {
    return await _storage.read(key: 'user_name');
  }

  static Future<void> logout() async {
    await _storage.deleteAll();
    _dio.options.headers.remove('Authorization');
    _dio.options.headers.remove('X-User-Phone');
  }

  // ── Auth ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> sendOTP(String phone) async {
    final res = await _dio.post('/auth/send-otp', data: {'phone': phone});
    return res.data;
  }

  static Future<Map<String, dynamic>> verifyOTP(
    String phone,
    String otp,
  ) async {
    final res = await _dio.post(
      '/auth/verify-otp',
      data: {'phone': phone, 'otp': otp},
    );
    await _storage.write(key: 'auth_token', value: res.data['token']);
    await _storage.write(key: 'user_phone', value: phone);
    final name = res.data['user']?['name'] ?? '';
    if (name.isNotEmpty) {
      await _storage.write(key: 'user_name', value: name);
    }
    _dio.options.headers['Authorization'] = 'Bearer ${res.data['token']}';
    _dio.options.headers['X-User-Phone'] = phone;

    final fcmToken = await _storage.read(key: 'fcm_token');
    if (fcmToken != null) {
      try {
        await _dio.post('/fcm-token', data: {'fcm_token': fcmToken});
        print('✅ FCM token updated successfully');
      } catch (e) {
        print('⚠️ FCM token update after login failed: $e');
      }
    }
    return res.data;
  }

  static Future<void> saveNameLocally(String name) async {
    await _storage.write(key: 'user_name', value: name);
  }

  static Future<void> saveGenderPreference(String gender) async {
    await _storage.write(key: 'gender_preference', value: gender);
  }

  static Future<String> getGenderPreference() async {
    return await _storage.read(key: 'gender_preference') ?? 'Other';
  }

  static Future<void> deleteBooking(String bookingRef) async {
    await setAuthHeader();
    await _dio.delete('/bookings/$bookingRef');
  }

  // ── Profile ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getProfile() async {
    await setAuthHeader();
    final res = await _dio.get('/profile');
    return res.data;
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String name,
    String? email,
  }) async {
    await setAuthHeader();
    final res = await _dio.put(
      '/profile',
      data: {
        'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
    return res.data;
  }

  // ── FCM Token ─────────────────────────────────────────────────
  static Future<void> updateFCMToken(String token) async {
    await setAuthHeader();
    await _dio.post('/fcm-token', data: {'fcm_token': token});
  }

  // ── Tents ─────────────────────────────────────────────────────
  static Future<List<dynamic>> getTents({String? classFilter}) async {
    final res = await _dio.get(
      '/tents',
      queryParameters: classFilter != null && classFilter != 'all'
          ? {'class': classFilter}
          : null,
    );
    return res.data['tents'];
  }

  static Future<Map<String, dynamic>> getTent(String id) async {
    final res = await _dio.get('/tents/$id');
    return res.data;
  }

  // ── Bookings ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> createBooking({
    required String tentId,
    required String checkIn,
    required String checkOut,
    required int guests,
    int units = 1,
    String? couponCode,
    Map<String, dynamic>? addons,
  }) async {
    await setAuthHeader();
    final res = await _dio.post(
      '/bookings',
      data: {
        'tent_id': int.parse(tentId),
        'check_in': checkIn,
        'check_out': checkOut,
        'guests': guests,
        'units': units,
        if (couponCode != null) 'coupon_code': couponCode,
        if (addons != null) 'addons': addons,
      },
    );
    return res.data;
  }

  static Future<List<dynamic>> getMyBookings() async {
    await setAuthHeader();
    final res = await _dio.get('/bookings');
    return res.data['bookings'] ?? [];
  }

  static Future<Map<String, dynamic>> cancelBooking(String bookingRef) async {
    await setAuthHeader();
    final res = await _dio.put('/bookings/$bookingRef/cancel');
    return res.data;
  }

  // ── Coupons ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>> validateCoupon({
    required String code,
    required double amount,
  }) async {
    await setAuthHeader();
    final res = await _dio.post(
      '/coupons/validate',
      data: {'code': code, 'amount': amount},
    );
    return res.data;
  }

  static Future<List<dynamic>> getCoupons() async {
    await setAuthHeader();
    final res = await _dio.get('/coupons');
    return res.data['coupons'] ?? [];
  }

  // ── Reviews ───────────────────────────────────────────────────
  static Future<void> submitReview({
    required String tentId,
    required String bookingRef,
    required int rating,
    String review = '',
  }) async {
    await setAuthHeader();
    await _dio.post(
      '/tents/$tentId/reviews',
      data: {'booking_ref': bookingRef, 'rating': rating, 'review': review},
    );
  }

  static Future<Map<String, dynamic>> getReviews(String tentId) async {
    final res = await _dio.get('/tents/$tentId/reviews');
    return res.data;
  }

  // ── Payments ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> verifyPayment({
    required String bookingRef,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    await setAuthHeader();
    final res = await _dio.post(
      '/payments/verify',
      data: {
        'booking_ref': bookingRef,
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      },
    );
    return res.data;
  }

  // ── KYC ───────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> submitKYC(
    String idType,
    String idNumber,
  ) async {
    await setAuthHeader();
    final res = await _dio.post(
      '/kyc',
      data: {'id_type': idType, 'id_number': idNumber},
    );
    return res.data;
  }
}
