/// Hanj's two shelves (Shahid, 2026-11-05: "masterpiece and favourites
/// should be the only shelves", and "you can only put 1 anime in one
/// shelve"). A shelf is still a name in the `tags` list on the show's own
/// entry, users/{uid}/animeList/{id}, so no new field or rule is needed.
///
/// Since Print Room P7 (2026-11-06) Favourites is no longer a shelf but a
/// mark of its own, beside whichever shelf the show is on, and the second
/// shelf is Hidden gems (Shahid: "replace favourite shelf with another
/// import thing but put favourite so users can show off their favourites
/// on the profile"); see [favouritesApart]. The mark is still the name
/// "Favourites" in `tags`, so lists from before need nothing rewritten.
///
/// Entries tagged before the rule can carry any names, several to an entry.
/// They are read through [shelfOf] and [isFavourite] and never rewritten: a
/// legacy name that means a shelf or the mark counts as it, every other
/// name is hidden, and an entry tagged with both shelves shows under
/// Masterpiece only. The status sheet writes the tags whole ([tagsFor]),
/// so the next time an entry's shelf or mark is picked there, its tags are
/// cleaned.
class HanjShelves {
  HanjShelves._();

  /// Favourites is a mark of its own and the second shelf is Hidden gems
  /// (P7). False gives back the rule of 2026-11-05: the two shelves are
  /// Masterpiece and Favourites, and nothing marks a favourite apart.
  static const bool favouritesApart = true;

  static const String masterpiece = 'Masterpiece';
  static const String favourites = 'Favourites';
  static const String hiddenGems = 'Hidden gems';

  /// Both shelves, in the order the status sheet and Profile show them.
  static const List<String> all = favouritesApart
      ? [masterpiece, hiddenGems]
      : [masterpiece, favourites];

  /// The shelf or mark a single tag names, or null for any other tag. Case
  /// and surrounding spaces don't matter; "Favorite", "Favorites",
  /// "Favourite" and "Favourites" all name Favourites, and "Hidden gem" and
  /// "Hidden gems" name Hidden gems.
  static String? named(String tag) => switch (tag.trim().toLowerCase()) {
        'masterpiece' => masterpiece,
        'favorite' || 'favorites' || 'favourite' || 'favourites' => favourites,
        'hidden gem' || 'hidden gems' when favouritesApart => hiddenGems,
        _ => null,
      };

  /// The one shelf an entry with these [tags] sits on, or null for none.
  /// Masterpiece when it's tagged with both. [tags] is the entry's `tags`
  /// field as stored; anything but a list of names puts it on no shelf.
  static String? shelfOf(Object? tags) {
    if (tags is! Iterable) return null;
    String? second;
    for (final tag in tags.whereType<String>()) {
      final shelf = named(tag);
      if (shelf == masterpiece) return masterpiece;
      if (shelf != null && all.contains(shelf)) second = shelf;
    }
    return second;
  }

  /// Whether an entry with these [tags] is one of your favourites (P7): any
  /// spelling of Favourites, beside any shelf. Never, with [favouritesApart]
  /// off, when Favourites is a shelf instead.
  static bool isFavourite(Object? tags) {
    if (!favouritesApart || tags is! Iterable) return false;
    return tags.whereType<String>().any((tag) => named(tag) == favourites);
  }

  /// The `tags` the status sheet writes for an entry on [shelf] (or none)
  /// and, if [favourite], marked as one: the whole list, so every legacy
  /// name goes. With [favouritesApart] off there is no mark to write.
  static List<String> tagsFor({required String? shelf, required bool favourite}) =>
      [
        ?shelf,
        if (favouritesApart && favourite) favourites,
      ];
}
