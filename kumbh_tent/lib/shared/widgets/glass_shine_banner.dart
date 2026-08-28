import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';

/// A frosted-glass banner container with a soft diagonal shine
/// that sweeps across it on a loop. Used to group the Explore
/// header (welcome + calendar) and search bar into one premium
/// hero panel.
class GlassShineBanner extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  const GlassShineBanner({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  @override
  State<GlassShineBanner> createState() => _GlassShineBannerState();
}

class _GlassShineBannerState extends State<GlassShineBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat(period: const Duration(milliseconds: 4200));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        children: [
          // ── Frosted glass base ─────────────────────────────
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.9),
                    AppColors.saffron.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.85),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                borderRadius: widget.borderRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),

          // ── Moving glass shine sweep ───────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // Sweep runs during the first ~55% of the cycle,
                  // then holds off-panel for a pause before looping.
                  final t = (_controller.value / 0.55).clamp(0.0, 1.0);
                  final dx = -1.4 + (t * 2.8);
                  return Transform.translate(
                    offset: Offset(
                      dx * MediaQuery.of(context).size.width,
                      0,
                    ),
                    child: Transform.rotate(
                      angle: -0.5,
                      child: Container(
                        width: 90,
                        height: MediaQuery.of(context).size.width * 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white.withValues(alpha: 0.55),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
