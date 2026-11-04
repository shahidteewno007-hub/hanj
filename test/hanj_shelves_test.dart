// Shelves (2026-11-05): only Masterpiece and Favourites, one per anime.
//
// Lists tagged before the rule are read, never rewritten, so the rule lives
// in how a tags field is read: any spelling of Favourites counts as it, every
// other name is hidden, and an entry tagged with both is on Masterpiece.

import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/models/hanj_shelves.dart';

void main() {
  test('the two shelves, in the order they show', () {
    expect(HanjShelves.all, ['Masterpiece', 'Favourites']);
  });

  test('a legacy name counts as a shelf whatever its case or spelling', () {
    for (final name in ['Masterpiece', 'masterpiece', ' MASTERPIECE ']) {
      expect(HanjShelves.named(name), HanjShelves.masterpiece, reason: name);
    }
    for (final name in ['Favorite', 'favorites', 'Favourite', 'FAVOURITES', ' Favourites']) {
      expect(HanjShelves.named(name), HanjShelves.favourites, reason: name);
    }
    for (final name in ['Action-Packed', 'Masterpieces', 'Fav', 'Favourite shows', '']) {
      expect(HanjShelves.named(name), isNull, reason: name);
    }
  });

  test('an entry sits on one shelf at most, Masterpiece over Favourites', () {
    // The shape of a real entry from before the rule: four shelves.
    expect(HanjShelves.shelfOf(['Masterpiece', 'Favorite', 'Action-Packed', 'Rewatch']), HanjShelves.masterpiece);
    expect(HanjShelves.shelfOf(['favorites', 'masterpiece']), HanjShelves.masterpiece);
    expect(HanjShelves.shelfOf(['Action-Packed', 'Favorite']), HanjShelves.favourites);
    expect(HanjShelves.shelfOf(['Favourites']), HanjShelves.favourites);
    expect(HanjShelves.shelfOf(['Action-Packed']), isNull);
  });

  test('a tags field that is missing or malformed puts it on no shelf', () {
    expect(HanjShelves.shelfOf(null), isNull);
    expect(HanjShelves.shelfOf(const <String>[]), isNull);
    expect(HanjShelves.shelfOf('Masterpiece'), isNull);
    expect(HanjShelves.shelfOf([1, null, 'Favourite']), HanjShelves.favourites);
    expect(HanjShelves.shelfOf({'Masterpiece'}), HanjShelves.masterpiece);
  });
}
