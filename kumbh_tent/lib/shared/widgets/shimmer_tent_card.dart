import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';

/// Skeleton placeholder shown while the tent list is loading,
/// matching the shape of the real tent card.
class ShimmerTentCard extends StatelessWidget {
  const ShimmerTentCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.softSurface,
      highlightColor: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.softSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 200,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 16, width: 160, color: Colors.white),
                  const SizedBox(height: 10),
                  Container(height: 12, width: 100, color: Colors.white),
                  const SizedBox(height: 14),
                  Container(height: 20, width: 90, color: Colors.white),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
