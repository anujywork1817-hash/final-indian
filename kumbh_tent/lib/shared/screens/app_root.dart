import 'package:flutter/material.dart';
import 'package:kumbh_tent/features/auth/screens/splash_screen.dart';

/// Single place Android back-navigation is handled for the whole app.
///
/// The app still has exactly ONE [Navigator] (built here), so
/// `showDialog`, `showModalBottomSheet`, `Navigator.of(context)`,
/// `Navigator.pop(context)`, `pushAndRemoveUntil`, bottom-nav, drawer
/// and iOS swipe-back all behave exactly as before — nothing is
/// nested or shadowed.
///
/// [RouterDelegate.popRoute] is Flutter's current, non-deprecated
/// hook for the Android system back button / predictive back gesture,
/// and it fires no matter how deep the user is:
///   • On any inner (pushed) screen → jump straight back to Home
///     (`popUntil` the first route), never the exit dialog.
///   • Already on Home              → hand off to [HomeScreen]'s own
///     PopScope (`maybePop`), which switches to the first tab if
///     needed and otherwise shows the exit-confirmation dialog.
class AppRouterDelegate extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // A bare Navigator doesn't get MaterialApp's HeroController, so give
  // it one or cross-screen Hero animations (e.g. tent images) stop.
  final HeroController _heroController = HeroController();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: [_heroController],
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => const SplashScreen(),
      ),
    );
  }

  // No deep-link / named-route handling — navigation is fully
  // imperative — so there is nothing to restore from a route path.
  @override
  Future<void> setNewRoutePath(Object configuration) async {}

  @override
  Future<bool> popRoute() async {
    final NavigatorState? nav = navigatorKey.currentState;
    if (nav == null) return false;

    if (nav.canPop()) {
      // Somewhere inside the app (Login, Dashboard, Profile, Settings,
      // tent detail, booking, …) → return to Home in one press.
      nav.popUntil((route) => route.isFirst);
      return true;
    }

    // First route is showing (Home once logged in). Forward the back
    // intent to it — HomeScreen's PopScope owns the tab-reset and the
    // exit-confirmation dialog. maybePop() still fires that callback
    // even though there is nothing to pop, and it returns true so the
    // app is never closed out from under us here.
    return nav.maybePop();
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }
}
