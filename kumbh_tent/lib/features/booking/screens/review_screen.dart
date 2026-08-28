import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/network/api_service.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';
import 'package:kumbh_tent/shared/widgets/premium_button.dart';

class ReviewScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  const ReviewScreen({super.key, required this.booking});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int _rating = 0;
  final _reviewController = TextEditingController();
  bool _isSubmitting = false;
  bool _isSubmitted = false;

  static const _tagOptions = [
    ('🧼', 'Clean'),
    ('🙋', 'Friendly staff'),
    ('📍', 'Great location'),
    ('💰', 'Value for money'),
    ('🛏️', 'Comfortable bed'),
    ('🍽️', 'Good food'),
  ];
  final Set<String> _selectedTags = {};

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      _snack('Please select a rating', AppColors.error);
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final tentId =
          (widget.booking['tent_id'] ??
                  widget.booking['id'] ??
                  widget.booking['ref'] ??
                  '')
              .toString();
      final tags = _selectedTags.isNotEmpty
          ? '${_selectedTags.map((t) => '#${t.replaceAll(' ', '')}').join(' ')}\n\n'
          : '';
      await ApiService.submitReview(
        tentId: tentId,
        bookingRef:
            widget.booking['booking_ref'] ?? widget.booking['ref'] ?? '',
        rating: _rating,
        review: '$tags${_reviewController.text.trim()}'.trim(),
      );
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isSubmitted = true;
        });
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _snack('Failed to submit review: $e', AppColors.error);
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _snack(String msg, Color color) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

  String get _ratingLabel {
    switch (_rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent!';
      default:
        return 'Tap a star to rate';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Rate Your Stay',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Tent info ──────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
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
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.saffron, AppColors.goldWarm],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('⛺', style: TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.booking['tent'] ?? widget.booking['tent_name'] ?? '',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.booking['location'] ?? '',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── 3D star rating ───────────────────────────────────
            Text(
              'How was your stay?',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _StarRating(
              rating: _rating,
              onChanged: (r) => setState(() => _rating = r),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _ratingLabel,
                key: ValueKey(_ratingLabel),
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  color: _rating == 0
                      ? AppColors.textMuted
                      : AppColors.saffronDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Quick sentiment tags ─────────────────────────────
            if (_rating > 0) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'What stood out?',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tagOptions.map((tag) {
                  final label = tag.$2;
                  final selected = _selectedTags.contains(label);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedTags.remove(label);
                      } else {
                        _selectedTags.add(label);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                                colors: [
                                  AppColors.saffron,
                                  AppColors.saffronDark,
                                ],
                              )
                            : null,
                        color: selected ? null : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppColors.saffron
                              : AppColors.cardBorder,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: AppColors.saffron.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        '${tag.$1} $label',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
            ],

            // ── Review text ───────────────────────────────────────
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Write a review',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _reviewController,
                maxLines: 5,
                maxLength: 300,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Share your experience... (optional)\n\nHow was the tent? Location? Staff?',
                  hintStyle: GoogleFonts.poppins(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.all(16),
                  counterStyle: GoogleFonts.poppins(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Submit button ──────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: _isSubmitted
                    ? Container(
                        key: const ValueKey('submitted'),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Thank you!',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _isSubmitting
                    ? Container(
                        key: const ValueKey('submitting'),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.saffron.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.2,
                            ),
                          ),
                        ),
                      )
                    : PremiumButton(
                        key: const ValueKey('submit'),
                        label: 'Submit Review',
                        icon: Icons.send_rounded,
                        verticalPadding: 16,
                        onPressed: _submitReview,
                      ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Five-star rating control styled like a raised 3D model rather
/// than a glowing string of lights: each star has a solid gold
/// face with a small embossed offset shadow for depth, jumps with
/// a bounce when tapped (staggered across the stars up to the
/// chosen rating), and shows a little smile badge only once it's
/// actually selected.
class _StarRating extends StatefulWidget {
  final int rating;
  final ValueChanged<int> onChanged;
  const _StarRating({required this.rating, required this.onChanged});

  @override
  State<_StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<_StarRating>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers = List.generate(
    5,
    (_) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    ),
  );

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _setRating(int rating) {
    widget.onChanged(rating);
    for (var i = 0; i < rating; i++) {
      Future.delayed(Duration(milliseconds: i * 70), () {
        if (mounted) _controllers[i].forward(from: 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final star = i + 1;
          final filled = star <= widget.rating;
          return GestureDetector(
            onTap: () => _setRating(star),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedBuilder(
                animation: _controllers[i],
                builder: (context, child) {
                  // A quick up-then-down jump — not a scale pop.
                  final t = _controllers[i].value;
                  final jump = t == 0
                      ? 0.0
                      : -14 * (4 * t * (1 - t)); // parabola, peaks mid-flight
                  return Transform.translate(
                    offset: Offset(0, jump),
                    child: child,
                  );
                },
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: filled
                      ? ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFFFFE9A8),
                              AppColors.goldWarm,
                              Color(0xFFB8860B),
                            ],
                            stops: [0.0, 0.55, 1.0],
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        )
                      : const Icon(
                          Icons.star_outline_rounded,
                          color: AppColors.border,
                          size: 40,
                        ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
