import 'package:flutter/material.dart';

/// Simple in-memory wishlist store (id set) shared across the app.
/// Not persisted — a lightweight placeholder until a backend
/// favorites endpoint exists.
class WishlistStore {
  WishlistStore._();
  static final WishlistStore instance = WishlistStore._();

  final ValueNotifier<Set<String>> ids = ValueNotifier<Set<String>>({});

  bool contains(String id) => ids.value.contains(id);

  void toggle(String id) {
    final next = Set<String>.from(ids.value);
    if (!next.remove(id)) next.add(id);
    ids.value = next;
  }
}

/// Animated heart button — scale + fade on toggle.
class WishlistButton extends StatefulWidget {
  final String tentId;
  final double size;

  const WishlistButton({super.key, required this.tentId, this.size = 18});

  @override
  State<WishlistButton> createState() => _WishlistButtonState();
}

class _WishlistButtonState extends State<WishlistButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    lowerBound: 0.85,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap() {
    WishlistStore.instance.toggle(widget.tentId);
    _controller.forward(from: 0.85);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: WishlistStore.instance.ids,
      builder: (context, ids, _) {
        final active = ids.contains(widget.tentId);
        return GestureDetector(
          onTap: _onTap,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ScaleTransition(
              scale: _controller,
              child: Icon(
                active ? Icons.favorite : Icons.favorite_border,
                color: active ? Colors.redAccent : Colors.black54,
                size: widget.size,
                semanticLabel: active
                    ? 'Remove from wishlist'
                    : 'Add to wishlist',
              ),
            ),
          ),
        );
      },
    );
  }
}
