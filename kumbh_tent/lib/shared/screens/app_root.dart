import 'package:flutter/material.dart';
import 'package:kumbh_tent/features/auth/screens/splash_screen.dart';
import 'package:kumbh_tent/features/home/screens/home_screen.dart';

/// Single place Android back-navigation is handled for the whole app.
///
/// The app still has exactly ONE [Navigator] (built here), so
/// `showDialog`, `showModalBottomSheet`, `Navigator.of(context)`,
/// `Navigator.pop(context)`, `pushAndRemoveUntil`, bottom-nav, drawer
/// and iOS swipe-back all behave exactly as before — nothing is
/// nested or shadowed.
///
/// BUG: this used to rely solely on [RouterDelegate.popRoute] to
/// catch the system back button / predictive back gesture. That hook
/// is the pre-predictive-back bridge — with
/// `android:enableOnBackInvokedCallback="true"` set (AndroidManifest,
/// required for the modern edge-swipe gesture), Android instead needs
/// a [PopScope] registered *from the moment a route becomes current*
/// to intercept the gesture and hold the frame; nothing here provided
/// one at the root. [HomeScreen]'s own PopScope is nested too far
/// down (inside an [IndexedStack] tab, itself under this bare
/// Navigator) to reliably win that registration on every tab, every
/// time — in practice the OS gesture (and sometimes the hardware
/// button) completed *before* popRoute() ever ran, closing the app
/// straight to the phone's home screen instead of stepping back to
/// the app's own Home tab.
///
/// The [PopScope] below wraps the Navigator itself with `canPop:
/// false`, so Flutter always holds the frame and always calls
/// [_handleBack] — for the hardware button, the 3-button nav bar, and
/// the edge-swipe gesture alike, no matter which of the 5 bottom-nav
/// tabs (or any pushed screen) is showing:
///   • Somewhere inside the app (tent detail, booking, profile
///     edit, …) → jump straight back to Home (`popUntil` the first
///     route), never the exit dialog.
///   • Already on Home              → forward to [HomeScreen]'s own
///     `handleBack()` (via [homeScreenKey]), which switches to the
///     first tab if needed and otherwise shows the "Are you sure you
///     want to exit?" confirmation.
class AppRouterDelegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // A bare Navigator doesn't get MaterialApp's HeroController, so give
  // it one or cross-screen Hero animations (e.g. tent images) stop.
  final HeroController _heroController = HeroController();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Navigator(
        key: navigatorKey,
        observers: [_heroController],
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => const SplashScreen(),
        ),
      ),
    );
  }

  Future<void> _handleBack() async {
    final NavigatorState? nav = navigatorKey.currentState;
    if (nav == null) return;

    if (nav.canPop()) {
      // Somewhere inside the app (Login, Dashboard, Profile, Settings,
      // tent detail, booking, …) → return to Home in one press.
      nav.popUntil((route) => route.isFirst);
      return;
    }

    // First route is showing (Home once logged in). homeScreenKey
    // points at whichever HomeScreen instance is actually mounted —
    // it owns the tab-reset and the exit-confirmation dialog.
    await homeScreenKey.currentState?.handleBack();
  }

  // No deep-link / named-route handling — navigation is fully
  // imperative — so there is nothing to restore from a route path.
  @override
  Future<void> setNewRoutePath(Object configuration) async {}

  // Kept as a fallback for the rare case something still dispatches
  // through the legacy channel instead of PopScope; _handleBack()
  // above is idempotent (worst case: tab-reset fires twice, a no-op
  // the second time) so double-handling here is harmless.
  @override
  Future<bool> popRoute() async {
    await _handleBack();
    return true;
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }
}
