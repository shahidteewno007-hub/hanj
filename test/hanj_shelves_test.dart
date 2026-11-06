// Shelves (2026-11-05): only Masterpiece and Favourites, one per anime.
// Since Print Room P7 (2026-11-06) Favourites is a mark of its own, beside
// any shelf, and the second shelf is Hidden gems (HanjShelves.favouritesApart).
//
// Lists tagged before the rule are read, never rewritten, so the rule lives
// in how a tags field is read: any spelling of a shelf or of Favourites counts
// as it, every other name is hidden, and an entry tagged with both shelves is
// on Masterpiece. The tests follow the switch, so the rule of 2026-11-05 keeps
// its tests while it's switched off.

import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/models/hanj_shelves.dart';

void main() {
  const apart = HanjShelves.favouritesApart;

  test('the two shelves, in the order they show', () {
    expect(HanjShelves.all,
        apart ? ['Masterpiece', 'Hidden gems'] : ['Masterpiece', 'Favourites']);
  });

  test('a legacy name counts as a shelf whatever its case or spelling', () {
    for (final name in ['Masterpiece', 'masterpiece', ' MASTERPIECE ']) {
      expect(HanjShelves.named(name), HanjShelves.masterpiece, reason: name);
    }
    for (final name in ['Favorite', 'favorites', 'Favourite', 'FAVOURITES', ' Favourites']) {
      expect(HanjShelves.named(name), HanjShelves.favourites, reason: name);
    }
    for (final name in ['Hidden gems', 'hidden gem', ' HIDDEN GEMS ']) {
      expect(HanjShelves.named(name), apart ? HanjShelves.hiddenGems : isNull,
          reason: name);
    }
    for (final name in ['Action-Packed', 'Masterpieces', 'Fav', 'Favourite shows', 'Gems', '']) {
      expect(HanjShelves.named(name), isNull, reason: name);
    }
  });

  test('an entry sits on one shelf at most, Masterpiece first', () {
    // The shape of a real entry from before the rule: four names.
    expect(HanjShelves.shelfOf(['Masterpiece', 'Favorite', 'Action-Packed', 'Rewatch']), HanjShelves.masterpiece);
    expect(HanjShelves.shelfOf(['favorites', 'masterpiece']), HanjShelves.masterpiece);
    expect(HanjShelves.shelfOf(['Hidden gems', 'Masterpiece']), HanjShelves.masterpiece);
    // Favourites is a shelf only under the rule of 2026-11-05.
    expect(HanjShelves.shelfOf(['Action-Packed', 'Favorite']), apart ? isNull : HanjShelves.favourites);
    expect(HanjShelves.shelfOf(['Favourites']), apart ? isNull : HanjShelves.favourites);
    expect(HanjShelves.shelfOf(['Favourites', 'Hidden gem']), apart ? HanjShelves.hiddenGems : HanjShelves.favourites);
    expect(HanjShelves.shelfOf(['Action-Packed']), isNull);
  });

  test('a favourite is a mark of its own, beside any shelf', () {
    // Bleach's shape: on Masterpiece, and a favourite through "Favorite".
    expect(HanjShelves.isFavourite(['Masterpiece', 'Favorite', 'Action-Packed', 'Rewatch']), apart);
    expect(HanjShelves.isFavourite(['Hidden gems', 'favourites']), apart);
    expect(HanjShelves.isFavourite([' Favourite ']), apart);
    expect(HanjShelves.isFavourite(['Masterpiece']), isFalse);
    expect(HanjShelves.isFavourite(['Favourite shows']), isFalse);
  });

  test('the tags written are the shelf and the mark, whole', () {
    expect(HanjShelves.tagsFor(shelf: HanjShelves.masterpiece, favourite: true),
        apart ? ['Masterpiece', 'Favourites'] : ['Masterpiece']);
    expect(HanjShelves.tagsFor(shelf: null, favourite: true), apart ? ['Favourites'] : isEmpty);
    expect(HanjShelves.tagsFor(shelf: HanjShelves.all.last, favourite: false), [HanjShelves.all.last]);
    expect(HanjShelves.tagsFor(shelf: null, favourite: false), isEmpty);
    // What a toggle on Bleach writes: its shelf and its mark, every other name gone.
    final bleach = ['Masterpiece', 'Favorite', 'Action-Packed', 'Rewatch'];
    expect(
        HanjShelves.tagsFor(
            shelf: HanjShelves.shelfOf(bleach),
            favourite: HanjShelves.isFavourite(bleach)),
        apart ? ['Masterpiece', 'Favourites'] : ['Masterpiece']);
  });

  test('a tags field that is missing or malformed puts it on no shelf', () {
    expect(HanjShelves.shelfOf(null), isNull);
    expect(HanjShelves.shelfOf(const <String>[]), isNull);
    expect(HanjShelves.shelfOf('Masterpiece'), isNull);
    expect(HanjShelves.shelfOf([1, null, 'Favourite']), apart ? isNull : HanjShelves.favourites);
    expect(HanjShelves.shelfOf([1, null, 'Hidden gems']), apart ? HanjShelves.hiddenGems : isNull);
    expect(HanjShelves.shelfOf({'Masterpiece'}), HanjShelves.masterpiece);
    expect(HanjShelves.isFavourite(null), isFalse);
    expect(HanjShelves.isFavourite('Favourites'), isFalse);
    expect(HanjShelves.isFavourite([1, null, 'Favourite']), apart);
  });
}
