import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:kumbh_tent/features/tents/screens/tent_detail_screen.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/features/tents/screens/search_screen.dart';

// ── Capsule tent images by class (local assets) ───────────────
const Map<String, List<String>> kCapsuleImages = {
  'standard': [
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

// ── Helper to load asset or network image ─────────────────────
Widget buildTentImage(
  String path, {
  BoxFit fit = BoxFit.cover,
  Widget? placeholder,
}) {
  final fallback =
      placeholder ??
      Container(
        color: kTrueSaffron.withOpacity(0.1),
        child: const Center(child: Text('⛺', style: TextStyle(fontSize: 60))),
      );
  if (path.startsWith('assets/')) {
    return Image.asset(path, fit: fit, errorBuilder: (_, __, ___) => fallback);
  }
  return CachedNetworkImage(
    imageUrl: path,
    fit: fit,
    placeholder: (_, __) => fallback,
    errorWidget: (_, __, ___) => fallback,
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
  List<Map<String, dynamic>> _tents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTents();
  }

  Future<void> _loadTents() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getTents(classFilter: _selectedClass);
      setState(() {
        _tents = data.map((t) {
          final tentClass = t['class'] as String;
          final images = List<String>.from(t['images'] ?? []);
          final displayImages = images.isNotEmpty
              ? images
              : (kCapsuleImages[tentClass] ?? kCapsuleImages['standard']!);
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
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      body: CustomScrollView(
        slivers: [
          // ── AppBar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 140,
            collapsedHeight: 140,
            pinned: true,
            floating: false,
            snap: false,
            forceElevated: true,
            backgroundColor: kTrueSaffron,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kTrueSaffronDark, kTrueSaffron],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to Simhastha Kumbh Nashik 2027',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Capsule Tent Booking',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Search bar
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SearchScreen(),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: kLuxGoldSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search,
                                  color: kTrueSaffron,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Search tents, location...',
                                  style: GoogleFonts.poppins(
                                    color: kLuxMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Peak dates banner ───────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kTrueSaffron.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kTrueSaffron.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ Peak pricing on Amrit Snan dates',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kTrueSaffronDark,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                ],
              ),
            ),
          ),

          // ── Class filter tabs ───────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                itemCount: kCapsuleTentClasses.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final isSel = kCapsuleTentClasses[i]['key'] == _selectedClass;
                  return GestureDetector(
                    onTap: () {
                      setState(
                        () => _selectedClass = kCapsuleTentClasses[i]['key']!,
                      );
                      _loadTents();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSel ? kTrueSaffron : kLuxGoldSoft,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSel
                              ? kTrueSaffronDark
                              : kTrueSaffron.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        kCapsuleTentClasses[i]['label']!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : kDark,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Tent list ───────────────────────────────────────
          _isLoading
              ? SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: kTrueSaffron),
                  ),
                )
              : _tents.isEmpty
              ? const SliverFillRemaining(
                  child: Center(child: Text('No tents found')),
                )
              : SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _CapsuleTentCard(tent: _tents[i]),
                      ),
                      childCount: _tents.length,
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _dateChip(String date, String surge) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: kLuxGoldSoft,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: kTrueSaffron.withOpacity(0.3)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          date,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: kDark,
          ),
        ),
        Text(
          surge,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: kTrueSaffron,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
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
    Color color;
    String label;
    switch (availability) {
      case 'sold_out':
        color = Colors.red.shade700;
        label = '⛔ Sold Out';
        break;
      case 'almost_full':
        color = Colors.red.shade400;
        label = '🔴 Only $available left!';
        break;
      case 'limited':
        color = Colors.orange.shade700;
        label = '🟡 $available Available';
        break;
      default:
        color = Colors.green.shade600;
        label = '🟢 Available';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Tent Card ──────────────────────────────────────────────────
class _CapsuleTentCard extends StatelessWidget {
  final Map<String, dynamic> tent;
  const _CapsuleTentCard({required this.tent});

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

  Color get _classColor {
    switch (tent['class']) {
      case 'standard':
        return const Color(0xFF0891B2);
      case 'luxury':
        return const Color(0xFF059669);
      case 'premium':
        return const Color(0xFF7C3AED);
      default:
        return kTrueSaffron;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSurge = tent['is_surge'] == true;
    final images = tent['images'] as List<String>;
    final firstImage = images.isNotEmpty ? images.first : null;
    final availability = tent['availability'] as String? ?? 'available';
    final available = tent['available'] as int? ?? 100;
    final isSoldOut = availability == 'sold_out';

    return GestureDetector(
      onTap: isSoldOut
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TentDetailScreen(tent: tent)),
            ),
      child: Opacity(
        opacity: isSoldOut ? 0.7 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: kLuxGoldSoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kTrueSaffron.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: kTrueSaffron.withOpacity(0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image section ────────────────────────────────
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: firstImage != null
                          ? buildTentImage(
                              firstImage,
                              placeholder: Container(
                                color: _classColor.withOpacity(0.15),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: kTrueSaffron,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: _classColor.withOpacity(0.15),
                              child: const Center(
                                child: Text(
                                  '⛺',
                                  style: TextStyle(fontSize: 60),
                                ),
                              ),
                            ),
                    ),
                  ),
                  // Class badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _classColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _classLabel,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  // Surge badge
                  if (isSurge)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '🔥 ${tent['surge']} Surge',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  // Availability badge
                  Positioned(
                    bottom: 10,
                    left: 12,
                    child: _AvailabilityBadge(
                      availability: availability,
                      available: available,
                    ),
                  ),
                  // Photos count
                  if (images.length > 1)
                    Positioned(
                      bottom: 10,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${images.length} photos',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              // ── Info section ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            tent['name'],
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: kDark,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: kTrueSaffron,
                              size: 16,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${tent['rating']}',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kDark,
                              ),
                            ),
                            Text(
                              ' (${tent['reviews']})',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: kLuxMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: kTrueSaffron,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            tent['location'],
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: kLuxMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getSizeInfo(),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: kLuxMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Amenity chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: (tent['amenities'] as List<String>)
                          .take(4)
                          .map(
                            (a) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: kTrueSaffron.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: kTrueSaffron.withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                a,
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: kTrueSaffronDark,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    // Price + Book button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '₹${tent['price']}/night',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: kDark,
                              ),
                            ),
                            Text(
                              '+ GST • Nashik Kumbh 2027',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: kLuxMuted,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSoldOut
                                ? kLuxMuted
                                : kTrueSaffron,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            elevation: 0,
                          ),
                          onPressed: isSoldOut
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        TentDetailScreen(tent: tent),
                                  ),
                                ),
                          child: Text(
                            isSoldOut ? 'Sold Out' : 'Book Now',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
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

  String _getSizeInfo() {
    switch (tent['class']) {
      case 'standard':
        return '2.25m × 4.75m × 2.5m • 2 Persons';
      case 'luxury':
        return '2.25m × 5.75m × 2.6m • 2-3 Persons';
      case 'premium':
        return '2.35m × 6.25m × 2.7m • 2-4 Persons';
      default:
        return '';
    }
  }
}
