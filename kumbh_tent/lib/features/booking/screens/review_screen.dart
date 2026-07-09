import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kumbh_tent/core/constants/constants.dart';
import 'package:kumbh_tent/core/network/api_service.dart';

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

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_rating == 0) {
      _snack('Please select a rating', Colors.red);
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
      await ApiService.submitReview(
        tentId: tentId,
        bookingRef:
            widget.booking['booking_ref'] ?? widget.booking['ref'] ?? '',
        rating: _rating,
        review: _reviewController.text.trim(),
      );
      if (mounted) {
        _snack('Review submitted! Thank you', Colors.green);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _snack('Failed to submit review: $e', Colors.red);
    } finally {
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
        return 'Tap to rate';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kTrueSaffronPale,
      appBar: AppBar(
        backgroundColor: kTrueSaffron,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Rate Your Stay',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),

            // Tent info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kLuxGoldSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    widget.booking['tent'] ?? widget.booking['tent_name'] ?? '',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: kDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.booking['location'] ?? '',
                    style: GoogleFonts.poppins(fontSize: 13, color: kLuxMuted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Star rating
            Text(
              'How was your stay?',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: kDark,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = star),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      star <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: star <= _rating ? kTrueSaffron : kLuxBorder,
                      size: 48,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              _ratingLabel,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: _rating == 0 ? kLuxMuted : kTrueSaffron,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 28),

            // Review text
            Container(
              decoration: BoxDecoration(
                color: kLuxGoldSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kTrueSaffron.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: kTrueSaffron.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _reviewController,
                maxLines: 5,
                maxLength: 300,
                style: GoogleFonts.poppins(fontSize: 14, color: kDark),
                decoration: InputDecoration(
                  hintText:
                      'Share your experience... (optional)\n\nHow was the tent? Location? Staff?',
                  hintStyle: GoogleFonts.poppins(
                    color: kLuxMuted,
                    fontSize: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: kLuxGoldSoft,
                  contentPadding: const EdgeInsets.all(16),
                  counterStyle: GoogleFonts.poppins(
                    color: kLuxMuted,
                    fontSize: 11,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTrueSaffron,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                onPressed: _isSubmitting ? null : _submitReview,
                child: _isSubmitting
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    : Text(
                        'Submit Review',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
