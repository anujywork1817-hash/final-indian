import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';
import 'package:kumbh_tent/features/booking/screens/my_bookings_screen.dart';
import 'package:kumbh_tent/features/profile/screens/profile_screen.dart';
import 'package:kumbh_tent/features/news/screens/news_screen.dart';
import 'package:kumbh_tent/features/history/screens/history_screen.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  // Explore stays at index 0 and Profile moves to the end; News and
  // History sit between Bookings and Profile.
  final List<Widget> _screens = [
    const BrowseScreen(),
    const MyBookingsScreen(),
    const NewsScreen(),
    const HistoryScreen(),
    const ProfileScreen(),
  ];

  Future<void> _handleBack() async {
    // Any tab other than Explore: back always returns to Explore
    // first, rather than exiting or popping an empty navigator.
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }
    final shouldExit = await _confirmExit();
    if (shouldExit && mounted) SystemNavigator.pop();
  }

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Exit App?',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to exit Kumbh Tent?',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                _navItem(0, Icons.explore_rounded, 'Explore'),
                _navItem(1, Icons.book_online_rounded, 'Bookings'),
                _navItem(2, Icons.newspaper_rounded, 'News'),
                _navItem(3, Icons.auto_stories_rounded, 'History'),
                _navItem(4, Icons.person_outline_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  // Wrapped in Expanded: with five tabs the old fixed 20px side
  // padding overflowed the row on narrow phones. Equal flex slots
  // scale instead of overflowing, so the labels stay on one line.
  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _currentIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.saffron.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isActive ? AppColors.saffron : AppColors.textMuted,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 10.5,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? AppColors.saffron : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
