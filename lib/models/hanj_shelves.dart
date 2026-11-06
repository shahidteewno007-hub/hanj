/// Hanj's two shelves (Shahid, 2026-11-05: "masterpiece and favourites
/// should be the only shelves", and "you can only put 1 anime in one
/// shelve"). A shelf is still a name in the `tags` list on the show's own
/// entry, users/{uid}/animeList/{id}, so no new field or rule is needed.
///
/// Entries tagged before the rule can carry any names, several to an entry.
/// They are read through [shelfOf] and never rewritten: a legacy name that
/// means one of the two shelves counts as it, every other name is hidden,
/// and an entry tagged with both shows under Masterpiece only. The status
/// sheet writes a single name, so the next time an entry's shelf is picked
/// there, its tags are cleaned.
class HanjShelves {
  HanjShelves._();

  static const String masterpiece = 'Masterpiece';
  static const String favourites = 'Favourites';

  /// Both shelves, in the order the status sheet and Profile show them.
  static const List<String> all = [masterpiece, favourites];

  /// The shelf a single tag names, or null for any other tag. Case and
  /// surrounding spaces don't matter, and "Favorite", "Favorites",
  /// "Favourite" and "Favourites" all name Favourites.
  static String? named(String tag) => switch (tag.trim().toLowerCase()) {
        'masterpiece' => masterpiece,
        'favorite' || 'favorites' || 'favourite' || 'favourites' => favourites,
        _ => null,
      };

  /// The one shelf an entry with these [tags] sits on, or null for none.
  /// Masterpiece when it's tagged with both. [tags] is the entry's `tags`
  /// field as stored; anything but a list of names puts it on no shelf.
  static String? shelfOf(Object? tags) {
    if (tags is! Iterable) return null;
    var favourite = false;
    for (final tag in tags.whereType<String>()) {
      final shelf = named(tag);
      if (shelf == masterpiece) return masterpiece;
      if (shelf == favourites) favourite = true;
    }
    return favourite ? favourites : null;
  }
}
