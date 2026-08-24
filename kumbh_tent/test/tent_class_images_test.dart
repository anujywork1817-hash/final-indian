import 'package:flutter_test/flutter_test.dart';
import 'package:kumbh_tent/core/constants/constants.dart';

/// Guards the tent-class → images mapping.
///
/// The browse screen builds every tent card from this. If a class
/// the API can return has no entry AND the fallback is missing,
/// the lookup throws, the whole list-mapping aborts, and the
/// screen silently keeps its previous contents — which reads to a
/// user as "the category filter does nothing".
void main() {
  // Exactly the values the backend stores in tents.class
  // (see kumbh_backend/schema.sql).
  const backendClasses = ['basic', 'standard', 'premium', 'luxury', 'vip'];

  test('every backend tent class resolves to a non-empty image list', () {
    for (final c in backendClasses) {
      final imgs = imagesForClass(c);
      expect(imgs, isNotEmpty, reason: 'class "$c" resolved to no images');
    }
  });

  test('unknown, empty and null classes fall back instead of throwing', () {
    for (final c in [null, '', 'deluxe', 'REGULAR', 'suite']) {
      expect(
        () => imagesForClass(c),
        returnsNormally,
        reason: 'class "$c" threw instead of falling back',
      );
      expect(imagesForClass(c), isNotEmpty);
    }
  });

  test('image paths all point at bundled assets', () {
    for (final c in backendClasses) {
      for (final path in imagesForClass(c)) {
        expect(
          path.startsWith('assets/images/'),
          isTrue,
          reason: '"$path" is not an asset path',
        );
      }
    }
  });

  // The filter chips must use keys the API actually accepts,
  // not display labels. 'regular' is a label; the API stores
  // 'standard'.
  test('kTentClasses keys are real API values or "all"', () {
    const valid = {'all', ...backendClasses};
    final keys = kTentClasses.map((e) => e['key']).toSet();
    final bogus = keys.difference(valid);

    expect(
      bogus,
      isEmpty,
      reason:
          'kTentClasses contains key(s) $bogus that no tent can ever have, '
          'so selecting them always yields an empty list',
    );
  });
}
