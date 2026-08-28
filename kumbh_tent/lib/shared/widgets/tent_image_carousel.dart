import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:kumbh_tent/core/theme/app_colors.dart';

/// Auto-sliding image carousel with manual swipe, page indicators
/// and an image counter. Pauses auto-slide while the user is
/// interacting, resumes shortly after.
class TentImageCarousel extends StatefulWidget {
  final List<String> images;
  final double height;
  final BorderRadius borderRadius;
  final String? heroTag;

  const TentImageCarousel({
    super.key,
    required this.images,
    this.height = 220,
    this.borderRadius = BorderRadius.zero,
    this.heroTag,
  });

  @override
  State<TentImageCarousel> createState() => _TentImageCarouselState();
}

class _TentImageCarouselState extends State<TentImageCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (widget.images.length > 1) _startAutoSlide();
  }

  void _startAutoSlide() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.images.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseThenResume() {
    _timer?.cancel();
    if (widget.images.length > 1) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _startAutoSlide();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _image(String path) {
    final fallback = Container(
      color: AppColors.saffron.withValues(alpha: 0.08),
      child: const Center(child: Text('⛺', style: TextStyle(fontSize: 48))),
    );
    if (path.startsWith('assets/')) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }
    return CachedNetworkImage(
      imageUrl: path,
      fit: BoxFit.cover,
      placeholder: (context, url) => fallback,
      errorWidget: (context, url, error) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images.isEmpty ? const ['']  : widget.images;
    Widget stack = SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification) _pauseThenResume();
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => images[i].isEmpty
                  ? Container(
                      color: AppColors.saffron.withValues(alpha: 0.08),
                      child: const Center(
                        child: Text('⛺', style: TextStyle(fontSize: 48)),
                      ),
                    )
                  : _image(images[i]),
            ),
          ),
          if (images.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: active ? 14 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          if (images.length > 1)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_page + 1}/${images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    stack = ClipRRect(borderRadius: widget.borderRadius, child: stack);

    if (widget.heroTag != null) {
      stack = Hero(tag: widget.heroTag!, child: stack);
    }
    return stack;
  }
}
