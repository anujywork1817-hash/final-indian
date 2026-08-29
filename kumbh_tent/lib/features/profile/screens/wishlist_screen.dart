import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/features/tents/screens/browse_screen.dart';
import 'package:kumbh_tent/features/tents/screens/tent_detail_screen.dart';
import 'package:kumbh_tent/shared/widgets/wishlist_button.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';
import 'package:kumbh_tent/shared/widgets/shimmer_tent_card.dart';

/// Shows every tent the user has hearted, sourced live from
/// [WishlistStore] (in-memory, per-device — see that file's own
/// note on why it isn't backed by an API yet).
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  List<Map<String, dynamic>> _allTents = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getTents();
      setState(() {
        _allTents = data
            .map(
              (t) => {
                'id': t['id'],
                'name': t['name'],
                'class': t['class'],
                'location': t['location'],
                'rating': t['rating'],
                'reviews': t['reviews'],
                'price': t['price'],
                'amenities': List<String>.from(t['amenities']),
                'images': List<String>.from(t['images'] ?? []),
                'color': kColorForClass(t['class']),
                'availability': t['availability'] ?? 'available',
                'available': t['available'] ?? 100,
                'is_surge': t['is_surge'],
                'surge': t['surge'],
                'distance': t['distance'],
              },
            )
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load your wishlist. Pull down to retry.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Wishlist',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoading
          ? ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: 3,
              itemBuilder: (context, i) => const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: SizedBox(height: 260, child: ShimmerTentCard()),
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 160,
                      child: PremiumButton(label: 'Retry', onPressed: _load),
                    ),
                  ],
                ),
              ),
            )
          : ValueListenableBuilder<Set<String>>(
              valueListenable: WishlistStore.instance.ids,
              builder: (context, ids, _) {
                final wishlisted = _allTents
                    .where((t) => ids.contains(t['id']?.toString() ?? ''))
                    .toList();
                if (wishlisted.isEmpty) return _emptyState();
                return RefreshIndicator(
                  color: AppColors.saffron,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: wishlisted.length,
                    separatorBuilder: (context, i) => const SizedBox(height: 16),
                    itemBuilder: (context, i) =>
                        _WishlistCard(tent: wishlisted[i]),
                  ),
                );
              },
            ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.saffron.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              size: 48,
              color: AppColors.saffron,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Your wishlist is empty',
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the heart on any tent to save it here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            child: PremiumButton(
              label: 'Explore Tents',
              icon: Icons.explore_rounded,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BrowseScreen()),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WishlistCard extends StatelessWidget {
  final Map<String, dynamic> tent;
  const _WishlistCard({required this.tent});

  @override
  Widget build(BuildContext context) {
    final images = tent['images'] as List<String>;
    final firstImage = images.isNotEmpty ? images.first : '';
    final tentId = tent['id']?.toString() ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TentDetailScreen(tent: tent)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(20),
              ),
              child: SizedBox(
                width: 110,
                height: 130,
                child: buildTentImage(firstImage),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tent['name'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        WishlistButton(tentId: tentId, size: 17),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tent['location'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: AppColors.goldWarm,
                          size: 14,
                        ),
                        Text(
                          ' ${tent['rating']}',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₹${tent['price']}/night',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.saffronDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
