import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kumbh_tent/shared/widgets/wishlist_button.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kumbh_tent/core/theme/app_theme.dart';
import 'package:kumbh_tent/features/auth/screens/splash_screen.dart';

// ── Background message handler ────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Background message: ${message.messageId}');
}

// ── Local notifications plugin ────────────────────────────
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ── Notification channel ──────────────────────────────────
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'bharat_tent_channel',
  'Bharat Tent Notifications',
  description: 'Booking confirmations and reminders',
  importance: Importance.high,
);

const _storage = FlutterSecureStorage();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase (push notifications) — Android/iOS only.
  // Skipped on web: this app's auth/booking flows go through the Go backend,
  // not Firebase, so Firebase is only needed for FCM push notifications,
  // which aren't set up for this web deployment.
  if (!kIsWeb) {
    await Firebase.initializeApp();

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize local notifications
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );
    await flutterLocalNotificationsPlugin.initialize(settings: initSettings);

    // Request notification permission
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get FCM token and save locally only
    // Will be sent to backend after user logs in
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint('FCM Token: $token');
    if (token != null) {
      await _storage.write(key: 'fcm_token', value: token);
    }

    // Listen for token refresh — save locally
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await _storage.write(key: 'fcm_token', value: newToken);
    });

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = message.notification?.android;
      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });
  }

  // Favourites are server-side now, so the local heart cache has to
  // be primed or every tent renders unsaved until the user toggles
  // one. Fire-and-forget: a slow network must not delay first paint,
  // and the store repaints itself via its ValueNotifier when it lands.
  unawaited(WishlistStore.instance.load());

  runApp(const ProviderScope(child: KumbhTentApp()));
}

class KumbhTentApp extends StatelessWidget {
  const KumbhTentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bharat Tent',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const SplashScreen(),
    );
  }
} 