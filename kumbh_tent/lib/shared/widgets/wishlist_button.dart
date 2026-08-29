import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kumbh_tent/core/network/api_service.dart';

/// Wishlist store, now backed by the server.
///
/// The in-memory Set is kept as a local cache so `contains()` stays
/// synchronous (every heart icon reads it during build) and the UI
/// can flip instantly. The network call runs behind that: optimistic
/// update first, rollback if the request fails, so a dropped
/// connection cannot leave the heart lying about what is saved.
class WishlistStore {
  WishlistStore._();
  static final WishlistStore instance = WishlistStore._();

  final ValueNotifier<Set<String>> ids = ValueNotifier<Set<String>>({});

  bool contains(String id) => ids.value.contains(id);

  /// Pulls the saved favourites down. Call after login and on app
  /// start, otherwise the hearts render empty until the first toggle.
  Future<void> load() async {
    try {
      final favs = await ApiService.getFavourites();
      ids.value = favs.map((f) => '${f['id']}').toSet();
    } catch (e) {
      debugPrint('wishlist: load failed: $e');
    }
  }

  Future<void> toggle(String id) async {
    final wasSaved = ids.value.contains(id);
    final next = Set<String>.from(ids.value);
    if (wasSaved) {
      next.remove(id);
    } else {
      next.add(id);
    }
    ids.value = next; // optimistic

    final tentId = int.tryParse(id);
    if (tentId == null) return; // non-numeric id: local-only, nothing to sync

    try {
      if (wasSaved) {
        await ApiService.removeFavourite(tentId);
      } else {
        await ApiService.addFavourite(tentId);
      }
    } catch (e) {
      // Put it back — the server never accepted the change.
      final revert = Set<String>.from(ids.value);
      if (wasSaved) {
        revert.add(id);
      } else {
        revert.remove(id);
      }
      ids.value = revert;
      debugPrint('wishlist: sync failed for $id: $e');
    }
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
    // Deliberately not awaited: toggle() updates the notifier
    // optimistically and rolls back on failure, so the animation
    // should not wait on the network round trip.
    unawaited(WishlistStore.instance.toggle(widget.tentId));
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
