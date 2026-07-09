import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/features/booking/screens/booking_form_screen.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';

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
    final Color color = tent['color'] as Color;

    final List<String> rawImages = List<String>.from(tent['images'] ?? []);
    final List<Map<String, String>> tentImages = rawImages
        .asMap()
        .entries
        .map((e) => {'url': e.value, 'label': 'Photo ${e.key + 1}'})
        .toList();

    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      body: CustomScrollView(
        slivers: [
          // ── Hero AppBar ─────────────────────────────────────
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: kTrueSaffron,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: kDark,
                  size: 18,
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _TentHeroImage(
                color: color,
                tentClass: tent['class'],
                images: tentImages,
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: kDark,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                color: kTrueSaffron,
                                size: 18,
                              ),
                              Text(
                                _loadingReviews
                                    ? ' ${tent['rating']}'
                                    : ' ${_avgRating.toStringAsFixed(1)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: kDark,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '$_totalReviews reviews',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: kLuxMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Location ──────────────────────────────────
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: kTrueSaffron,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          tent['location'],
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: kLuxMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kTrueSaffron.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: kTrueSaffron.withOpacity(0.25),
                          ),
                        ),
                        child: Text(
                          '${tent['distance']} km from Sangam',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: kTrueSaffron,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Surge banner ──────────────────────────────
                  if (isSurge)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Text('🔥', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Surge Pricing Active',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Price is ${tent['surge']} of base due to Kumbh peak dates',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.red.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

                  // ── Amenities ─────────────────────────────────
                  Text(
                    'Amenities',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: (tent['amenities'] as List<String>)
                        .map(
                          (a) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: kLuxGoldSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: kTrueSaffron.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: kTrueSaffron,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  a,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: kDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),

                  // ── Policies ──────────────────────────────────
                  Text(
                    'Policies',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _policyRow(Icons.access_time, 'Check-in: 12:00 PM'),
                  _policyRow(Icons.logout, 'Check-out: 11:00 AM'),
                  _policyRow(
                    Icons.cancel_outlined,
                    'Free cancellation 48hrs before',
                  ),
                  _policyRow(Icons.no_meals, 'No outside food allowed'),
                  const SizedBox(height: 20),

                  // ── Reviews ───────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Guest Reviews',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kDark,
                        ),
                      ),
                      if (_totalReviews > 0)
                        Row(
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: kTrueSaffron,
                              size: 16,
                            ),
                            Text(
                              ' ${_avgRating.toStringAsFixed(1)} · $_totalReviews reviews',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kDark,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_loadingReviews)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: kTrueSaffron),
                      ),
                    )
                  else if (_reviews.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: kLuxGoldSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: kTrueSaffron.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text('⭐', style: TextStyle(fontSize: 32)),
                          const SizedBox(height: 8),
                          Text(
                            'No reviews yet',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: kDark,
                            ),
                          ),
                          Text(
                            'Be the first to review!',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: kLuxMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._reviews.take(5).map((r) => _ReviewCard(review: r)),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom bar ────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: kTrueSaffron,
            boxShadow: [
              BoxShadow(
                color: kTrueSaffronDark.withOpacity(0.3),
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
                        color: Colors.white60,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  Text(
                    '₹${tent['price']}',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'per night + taxes',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kTrueSaffronDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookingFormScreen(tent: tent),
                    ),
                  ),
                  child: Text(
                    'Book Now 🪔',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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

  Widget _policyRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, color: kTrueSaffron, size: 16),
        const SizedBox(width: 8),
        Text(text, style: GoogleFonts.poppins(fontSize: 13, color: kLuxMuted)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kLuxGoldSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kTrueSaffron.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: kTrueSaffron.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                    color: kTrueSaffron,
                    size: 18,
                  ),
                ),
              ),
              Text(
                phone,
                style: GoogleFonts.poppins(fontSize: 11, color: kLuxMuted),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(text, style: GoogleFonts.poppins(fontSize: 13, color: kDark)),
          ],
        ],
      ),
    );
  }
}

// ── Hero image ─────────────────────────────────────────────────
class _TentHeroImage extends StatelessWidget {
  final Color color;
  final dynamic tentClass;
  final List<Map<String, String>> images;

  const _TentHeroImage({
    required this.color,
    required this.tentClass,
    required this.images,
  });

  Widget _placeholder() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [kTrueSaffronDark, kTrueSaffron],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('⛺', style: TextStyle(fontSize: 100)),
        Text(
          '$tentClass'.toUpperCase(),
          style: GoogleFonts.poppins(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return _placeholder();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.black,
          transitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (ctx, anim, _) => FadeTransition(
            opacity: anim,
            child: _TentGalleryScreen(images: images),
          ),
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          buildTentImage(images.first['url']!, placeholder: _placeholder()),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.transparent,
                    Colors.black.withOpacity(0.5),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Text(
              '$tentClass'.toUpperCase(),
              style: GoogleFonts.poppins(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ),
          Positioned(
            bottom: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt, color: Colors.white, size: 13),
                  const SizedBox(width: 5),
                  Text(
                    '${images.length} photos',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gallery screen ─────────────────────────────────────────────
class _TentGalleryScreen extends StatefulWidget {
  final List<Map<String, String>> images;
  final int initialIndex;
  const _TentGalleryScreen({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

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
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
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
                          widget.images[i]['url']!,
                          fit: BoxFit.contain,
                          placeholder: Container(
                            color: const Color(0xFF3D2000),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: kTrueSaffron,
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
                          color: isActive ? kTrueSaffron : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Opacity(
                          opacity: isActive ? 1.0 : 0.45,
                          child: buildTentImage(widget.images[i]['url']!),
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
  const _Arrow({super.key, required this.icon, required this.onTap});

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
