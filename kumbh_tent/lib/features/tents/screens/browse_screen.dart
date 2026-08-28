import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/features/tents/screens/tent_detail_screen.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/features/tents/screens/search_screen.dart';
import 'package:kumbh_tent/features/kumbh/screens/snan_calendar_screen.dart';
import 'package:kumbh_tent/core/constants/snan_calendar.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/shared/widgets/premium_badge.dart';
import 'package:kumbh_tent/shared/widgets/wishlist_button.dart';
import 'package:kumbh_tent/shared/widgets/tent_image_carousel.dart';
import 'package:kumbh_tent/shared/widgets/shimmer_tent_card.dart';
import 'package:kumbh_tent/shared/widgets/glass_shine_banner.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

// Tent images live in core/constants/constants.dart as
// kCapsuleImages / imagesForClass. A second copy used to be
// declared here, shadowing the shared one — two maps with
// different keys that silently drifted apart. Worse, every file
// importing both this screen and constants.dart was one
// reference away from an ambiguous-import error.

// ── Helper to load asset or network image (used elsewhere) ────
Widget buildTentImage(
  String path, {
  BoxFit fit = BoxFit.cover,
  Widget? placeholder,
}) {
  final fallback =
      placeholder ??
      Container(
        color: AppColors.saffron.withValues(alpha: 0.08),
        child: const Center(child: Text('⛺', style: TextStyle(fontSize: 60))),
      );
  if (path.startsWith('assets/')) {
    return Image.asset(
      path,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
  return Image.network(
    path,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}

// ── Tent class filter tabs ─────────────────────────────────────
const List<Map<String, String>> kCapsuleTentClasses = [
  {'key': 'all', 'label': 'All'},
  {'key': 'standard', 'label': 'Regular'},
  {'key': 'luxury', 'label': 'Luxury'},
  {'key': 'premium', 'label': 'Premium'},
];

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  String _selectedClass = 'all';
  String? _loadError;
  List<Map<String, dynamic>> _tents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTents();
  }

  Future<void> _loadTents() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final data = await ApiService.getTents(classFilter: _selectedClass);
      final mapped = data.map((t) {
        final tentClass = (t['class'] ?? '') as String;
        final images = List<String>.from(t['images'] ?? []);
        // imagesForClass never returns null, so a class with no
        // artwork can no longer abort the whole list.
        final displayImages = images.isNotEmpty
            ? images
            : imagesForClass(tentClass);
        return {
          'id': t['id'],
          'name': t['name'],
          'class': tentClass,
          'location': t['location'],
          'distance': t['distance'],
          'rating': t['rating'],
          'reviews': t['reviews'],
          'price': t['price'],
          'base_price': t['base_price'],
          'is_surge': t['is_surge'],
          'surge': t['surge'],
          'amenities': List<String>.from(t['amenities']),
          'images': displayImages,
          'color': kColorForClass(tentClass),
          'availability': t['availability'] ?? 'available',
          'available': t['available'] ?? 100,
          'capacity': t['capacity'] ?? 100,
          'cancellation_policy_type': t['cancellation_policy_type'],
          'free_cancellation_hours': t['free_cancellation_hours'],
          'partial_refund_penalty_percent': t['partial_refund_penalty_percent'],
          'late_cancellation_hours': t['late_cancellation_hours'],
          'no_show_cutoff_hours': t['no_show_cutoff_hours'],
          'no_show_penalty_percent': t['no_show_penalty_percent'],
        };
      }).toList();

      setState(() {
        _tents = List<Map<String, dynamic>>.from(mapped);
        _isLoading = false;
      });
    } catch (e) {
      // Previously this swallowed the error and left _tents at its
      // previous value, so a failed load looked exactly like "the
      // filter did nothing". Clear the list and say what happened.
      setState(() {
        _tents = [];
        _isLoading = false;
        _loadError = 'Could not load tents. Pull down to retry.';
      });
      debugPrint('loadTents failed for class=$_selectedClass: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.saffron,
          onRefresh: _loadTents,
          child: CustomScrollView(
            slivers: [
              // ── Hero banner: welcome + calendar + search ───────
              SliverToBoxAdapter(child: _buildHeroBanner()),

              // ── Peak pricing ──────────────────────────────────
              SliverToBoxAdapter(child: _buildPeakPricing()),

              // ── Category chips ────────────────────────────────
              SliverToBoxAdapter(child: _buildCategoryChips()),

              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // ── Tent list ───────────────────────────────────
              _buildTentList(),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero glass banner: full-width, scrolls with the page ──────
  Widget _buildHeroBanner() {
    return GlassShineBanner(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome to',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Simhastha Kumbh Nashik 2027',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Find Your Perfect Stay',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _calendarButton(),
              ],
            ),
            const SizedBox(height: 16),
            _searchField(),
          ],
      ),
    );
  }

  Widget _searchField() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SearchScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: AppColors.saffron,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Where would you like to stay?',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Nashik • Dates • Guests',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _calendarButton() {
    final upcoming = kUpcomingSnans;
    final nextIsAmrit = upcoming.isNotEmpty && upcoming.first.isAmrit;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SnanCalendarScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.softSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
            if (nextIsAmrit)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.saffron,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Compact peak pricing card ─────────────────────────────────
  Widget _buildPeakPricing() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.goldWarm.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.goldWarm.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  'Peak dates',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _dateChip('Aug 2', '2x'),
                  _dateChip('Aug 31', '2.5x'),
                  _dateChip('Sep 11', '3x'),
                  _dateChip('Sep 12', '3x'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Prices increase during high-demand bathing dates.',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(String date, String surge) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          date,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          surge,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: AppColors.saffron,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  // ── Category filter chips ─────────────────────────────────────
  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: kCapsuleTentClasses.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSel = kCapsuleTentClasses[i]['key'] == _selectedClass;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedClass = kCapsuleTentClasses[i]['key']!);
              _loadTents();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isSel ? AppColors.saffron : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSel ? AppColors.saffron : AppColors.border,
                ),
              ),
              child: Center(
                child: Text(
                  kCapsuleTentClasses[i]['label']!,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSel ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Tent list / loading / empty / error states ────────────────
  Widget _buildTentList() {
    if (_isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.all(20),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) =>
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: SizedBox(height: 320, child: ShimmerTentCard()),
                ),
            childCount: 3,
          ),
        ),
      );
    }

    if (_tents.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _loadError != null ? '😕' : '⛺',
                  style: const TextStyle(fontSize: 44),
                ),
                const SizedBox(height: 12),
                Text(
                  _loadError ?? 'No tents in this category',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 160,
                  child: PremiumButton(label: 'Retry', onPressed: _loadTents),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 300 + (i * 60)),
            curve: Curves.easeOut,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 16),
                child: child,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _PremiumTentCard(tent: _tents[i]),
            ),
          ),
          childCount: _tents.length,
        ),
      ),
    );
  }
}

// ── Availability Badge ─────────────────────────────────────────
class _AvailabilityBadge extends StatelessWidget {
  final String availability;
  final int available;
  const _AvailabilityBadge({
    required this.availability,
    required this.available,
  });

  @override
  Widget build(BuildContext context) {
    switch (availability) {
      case 'sold_out':
        return const PremiumBadge(
          label: 'SOLD OUT',
          style: PremiumBadgeStyle.danger,
        );
      case 'almost_full':
        return PremiumBadge(
          label: 'ONLY $available LEFT',
          style: PremiumBadgeStyle.danger,
        );
      case 'limited':
        return PremiumBadge(
          label: '$available AVAILABLE',
          style: PremiumBadgeStyle.gold,
        );
      default:
        return const PremiumBadge(
          label: 'AVAILABLE',
          style: PremiumBadgeStyle.success,
        );
    }
  }
}

// ── Premium Tent Card ────────────────────────────────────────────
class _PremiumTentCard extends StatelessWidget {
  final Map<String, dynamic> tent;
  const _PremiumTentCard({required this.tent});

  String get _classLabel {
    switch (tent['class']) {
      case 'standard':
        return 'REGULAR';
      case 'luxury':
        return 'LUXURY';
      case 'premium':
        return 'PREMIUM';
      default:
        return tent['class'].toString().toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSurge = tent['is_surge'] == true;
    final images = tent['images'] as List<String>;
    final availability = tent['availability'] as String? ?? 'available';
    final available = tent['available'] as int? ?? 100;
    final isSoldOut = availability == 'sold_out';
    final tentId = tent['id']?.toString() ?? '';

    return GestureDetector(
      onTap: isSoldOut
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TentDetailScreen(tent: tent)),
            ),
      child: Opacity(
        opacity: isSoldOut ? 0.6 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image carousel section ────────────────────────
              Stack(
                children: [
                  TentImageCarousel(
                    images: images,
                    height: 200,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: PremiumBadge(
                      label: _classLabel,
                      style: tent['class'] == 'premium'
                          ? PremiumBadgeStyle.gold
                          : PremiumBadgeStyle.dark,
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: WishlistButton(tentId: tentId),
                  ),
                  if (isSurge)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: PremiumBadge(
                        label: '${tent['surge']} SURGE',
                        style: PremiumBadgeStyle.danger,
                        icon: Icons.local_fire_department_rounded,
                      ),
                    ),
                ],
              ),

              // ── Info section ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tent['name'],
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: AppColors.goldWarm,
                          size: 16,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${tent['rating']}',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          ' (${tent['reviews']})  •  ',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.textMuted,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            tent['location'],
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: (tent['amenities'] as List<String>)
                          .take(4)
                          .map(
                            (a) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.softSurface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                a,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    _AvailabilityBadge(
                      availability: availability,
                      available: available,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'From',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            Text(
                              '₹${tent['price']}/night',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '+ GST',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 140,
                          child: PremiumButton(
                            label: isSoldOut ? 'Sold Out' : 'View Details',
                            verticalPadding: 12,
                            onPressed: isSoldOut
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          TentDetailScreen(tent: tent),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
