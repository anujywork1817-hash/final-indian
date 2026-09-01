import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/features/booking/screens/booking_form_screen.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';
import 'package:kumbh_tent/shared/widgets/premium_badge.dart';
import 'package:kumbh_tent/shared/widgets/wishlist_button.dart';
import 'package:kumbh_tent/shared/widgets/tent_image_carousel.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

class TentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> tent;
  const TentDetailScreen({super.key, required this.tent});

  @override
  State<TentDetailScreen> createState() => _TentDetailScreenState();
}

class _TentDetailScreenState extends State<TentDetailScreen> {
  List<dynamic> _reviews = [];
  double _avgRating = 0;
  int _totalReviews = 0;
  bool _loadingReviews = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final tentId = widget.tent['id']?.toString() ?? '';
      if (tentId.isEmpty) return;
      final data = await ApiService.getReviews(tentId);
      setState(() {
        _reviews = data['reviews'] ?? [];
        _avgRating = (data['avg_rating'] ?? 0).toDouble();
        _totalReviews = data['total'] ?? 0;
        _loadingReviews = false;
      });
    } catch (e) {
      setState(() => _loadingReviews = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tent = widget.tent;
    final bool isSurge = tent['is_surge'] == true;
    final tentId = tent['id']?.toString() ?? '';

    final List<String> images = List<String>.from(tent['images'] ?? []);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Hero image carousel ──────────────────────────────
          SliverToBoxAdapter(
            child: _HeroGallery(
              images: images,
              tentClass: '${tent['class']}',
              tentId: tentId,
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Name + Rating ─────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          tent['name'],
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: AppColors.goldWarm,
                                size: 18,
                              ),
                              Text(
                                _loadingReviews
                                    ? ' ${tent['rating']}'
                                    : ' ${_avgRating.toStringAsFixed(1)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '$_totalReviews reviews',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Location ──────────────────────────────────
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: AppColors.saffron,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          tent['location'],
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${tent['distance']} km from Sangam',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Surge banner ──────────────────────────────
                  if (isSurge)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: AppColors.error,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Surge Pricing Active',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.error,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Price is ${tent['surge']} of base due to Kumbh peak dates',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: AppColors.error.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isSurge) const SizedBox(height: 16),

                  // ── Amenities ─────────────────────────────────
                  _sectionTitle('Amenities'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: (tent['amenities'] as List<String>)
                        .map(
                          (a) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.softSurface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.saffron,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  a,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),

                  // ── Policies ──────────────────────────────────
                  _sectionTitle('Policies'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
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
                      children: [
                        _policyRow(Icons.login_rounded, 'Check-in: 12:00 PM'),
                        _policyRow(Icons.logout_rounded, 'Check-out: 11:00 AM'),
                        _policyRow(
                          Icons.cancel_outlined,
                          'Free cancellation 48hrs before',
                        ),
                        _policyRow(
                          Icons.no_meals_rounded,
                          'No outside food allowed',
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Reviews ───────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionTitle('Guest Reviews'),
                      if (_totalReviews > 0)
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: AppColors.goldWarm,
                              size: 16,
                            ),
                            Text(
                              ' ${_avgRating.toStringAsFixed(1)} · $_totalReviews reviews',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (_loadingReviews)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          color: AppColors.saffron,
                        ),
                      ),
                    )
                  else if (_reviews.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.softSurface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.star_border_rounded,
                            size: 34,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No reviews yet',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Be the first to review!',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._reviews.take(5).map((r) => _ReviewCard(review: r)),

                  const SizedBox(height: 110),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Sticky booking CTA ────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSurge)
                    Text(
                      '₹${tent['base_price']}/night',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    '₹${tent['price']}',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'per night + taxes',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: PremiumButton(
                  label: 'Book Now',
                  icon: Icons.bolt_rounded,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookingFormScreen(tent: tent),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
  );

  Widget _policyRow(IconData icon, String text, {bool isLast = false}) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.saffron.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.saffron, size: 15),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );
}

// ── Review card ────────────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final dynamic review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final rating = review['rating'] ?? 0;
    final text = review['review'] ?? '';
    final phone = review['phone'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppColors.goldWarm,
                    size: 18,
                  ),
                ),
              ),
              Text(
                phone,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Hero gallery: auto-sliding carousel + back/wishlist overlay ──
class _HeroGallery extends StatelessWidget {
  final List<String> images;
  final String tentClass;
  final String tentId;

  const _HeroGallery({
    required this.images,
    required this.tentClass,
    required this.tentId,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: images.isEmpty
          ? null
          : () => Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                barrierColor: Colors.black,
                transitionDuration: const Duration(milliseconds: 250),
                pageBuilder: (ctx, anim, secondaryAnim) => FadeTransition(
                  opacity: anim,
                  child: _TentGalleryScreen(images: images),
                ),
              ),
            ),
      child: Stack(
        children: [
          TentImageCarousel(images: images, height: 340),
          Positioned(
            left: 16,
            top: 16,
            child: SafeArea(
              bottom: false,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: AppColors.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: SafeArea(
              bottom: false,
              child: WishlistButton(tentId: tentId, size: 20),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: PremiumBadge(
              label: tentClass.toUpperCase(),
              style: tentClass == 'premium'
                  ? PremiumBadgeStyle.gold
                  : PremiumBadgeStyle.dark,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Full-screen gallery ─────────────────────────────────────────
class _TentGalleryScreen extends StatefulWidget {
  final List<String> images;
  const _TentGalleryScreen({required this.images});

  @override
  State<_TentGalleryScreen> createState() => _TentGalleryScreenState();
}

class _TentGalleryScreenState extends State<_TentGalleryScreen> {
  late PageController _pageController;
  late ScrollController _thumbController;
  int _current = 0;

  static const double _thumbSize = 64.0;
  static const double _thumbGap = 8.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _thumbController = ScrollController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    setState(() => _current = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (_thumbController.hasClients) {
      final offset = (index * (_thumbSize + _thumbGap)) - _thumbSize;
      _thumbController.animateTo(
        offset.clamp(0.0, _thumbController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  Text(
                    'Photos',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _current = i),
                    itemCount: widget.images.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: buildTentImage(
                          widget.images[i],
                          fit: BoxFit.contain,
                          placeholder: Container(
                            color: const Color(0xFF1A1A1A),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.saffron,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_current > 0)
                    Positioned(
                      left: 4,
                      child: _Arrow(
                        icon: Icons.chevron_left,
                        onTap: () => _goTo(_current - 1),
                      ),
                    ),
                  if (_current < widget.images.length - 1)
                    Positioned(
                      right: 4,
                      child: _Arrow(
                        icon: Icons.chevron_right,
                        onTap: () => _goTo(_current + 1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_current + 1} / ${widget.images.length}',
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: _thumbSize + 4,
              child: ListView.builder(
                controller: _thumbController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.images.length,
                itemBuilder: (ctx, i) {
                  final isActive = i == _current;
                  return GestureDetector(
                    onTap: () => _goTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _thumbSize,
                      height: _thumbSize,
                      margin: EdgeInsets.only(right: _thumbGap),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                              ? AppColors.saffron
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Opacity(
                          opacity: isActive ? 1.0 : 0.45,
                          child: buildTentImage(widget.images[i]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Arrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    ),
  );
}
