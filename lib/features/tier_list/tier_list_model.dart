// Tier lists (round seven): the data a tier list is made of, and every edit
// the editor can make to it. Plain Dart, no Flutter, so the rules are tested
// on their own (test/tier_list_model_test.dart).
//
// A list is a set of tiers, top first, plus an "unranked" tray of characters
// picked but not placed yet. Every character on the list sits in exactly one
// of those places, once. The edits below keep that true, so the editor never
// has to.
//
// Saved lists live on the device only (tier_list_store.dart): a Firestore
// collection would need a rules change and deploy, which is Shahid's step.

/// One character on a tier list, as AniList described them when they were
/// picked: enough to draw the portrait and caption without asking again.
class TierCharacter {
  const TierCharacter({
    required this.id,
    required this.name,
    this.imageUrl,
    this.mediaId,
    this.mediaTitle,
    this.mediaCover,
    this.mediaColor,
  });

  /// AniList's character id.
  final int id;
  final String name;

  /// The portrait (AniList's `image.large`, 2:3).
  final String? imageUrl;

  /// The anime they were picked from, when known.
  final int? mediaId;
  final String? mediaTitle;
  final String? mediaCover;

  /// That anime's `coverImage.color`, as a 0xAARRGGBB value.
  final int? mediaColor;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (imageUrl != null) 'image': imageUrl,
        if (mediaId != null) 'mediaId': mediaId,
        if (mediaTitle != null) 'mediaTitle': mediaTitle,
        if (mediaCover != null) 'mediaCover': mediaCover,
        if (mediaColor != null) 'mediaColor': mediaColor,
      };

  static TierCharacter? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String) return null;
    return TierCharacter(
      id: id,
      name: name,
      imageUrl: json['image'] as String?,
      mediaId: json['mediaId'] as int?,
      mediaTitle: json['mediaTitle'] as String?,
      mediaCover: json['mediaCover'] as String?,
      mediaColor: json['mediaColor'] as int?,
    );
  }

  /// AniList's `coverImage.color` ("#e4a15d") as 0xFFRRGGBB, or null.
  static int? parseHexColor(String? hex) {
    if (hex == null) return null;
    final s = hex.startsWith('#') ? hex.substring(1) : hex;
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : 0xFF000000 | v;
  }
}

/// One row of a tier list.
class Tier {
  Tier({
    required this.id,
    required this.label,
    required this.pigment,
    List<int>? characterIds,
  }) : characterIds = characterIds ?? <int>[];

  /// Stable within its list, so a renamed tier keeps its place on screen.
  final String id;
  String label;

  /// An index into `TierPigment.all` (tier_list_templates.dart).
  int pigment;

  /// Left to right: the order inside a tier is part of the verdict.
  final List<int> characterIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'pigment': pigment,
        'characters': characterIds,
      };

  static Tier? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    return Tier(
      id: id,
      label: (json['label'] as String?) ?? '',
      pigment: (json['pigment'] as int?) ?? 0,
      characterIds: [
        for (final c in (json['characters'] as List?) ?? const [])
          if (c is int) c,
      ],
    );
  }
}

/// A whole tier list.
class TierList {
  TierList({
    required this.id,
    required this.title,
    this.prompt = '',
    this.templateId = 'custom',
    required this.tiers,
    List<int>? unranked,
    Map<int, TierCharacter>? characters,
    required this.createdAt,
    DateTime? updatedAt,
  })  : unranked = unranked ?? <int>[],
        characters = characters ?? <int, TierCharacter>{},
        updatedAt = updatedAt ?? createdAt;

  /// The most characters one list holds: about 24 rows of five on the
  /// exported image, which is still a picture people can read.
  static const int maxCharacters = 120;

  /// Fewest and most tiers. One tier is a list, not a ranking; past twelve
  /// the exported image stops fitting a phone screen in two swipes.
  static const int minTiers = 1;
  static const int maxTiers = 12;

  /// The longest tier name, in characters.
  static const int maxLabelLength = 24;
  static const int maxTitleLength = 60;

  final String id;
  String title;
  String prompt;
  final String templateId;
  final List<Tier> tiers;
  final List<int> unranked;
  final Map<int, TierCharacter> characters;
  final DateTime createdAt;
  DateTime updatedAt;

  int get count => characters.length;
  int get rankedCount => count - unranked.length;
  bool get isFull => count >= maxCharacters;
  bool get isEmpty => characters.isEmpty;

  bool contains(int characterId) => characters.containsKey(characterId);

  /// The tier holding [characterId], or null when it is unranked or absent.
  Tier? tierOf(int characterId) {
    for (final t in tiers) {
      if (t.characterIds.contains(characterId)) return t;
    }
    return null;
  }

  Tier? tierById(String id) {
    for (final t in tiers) {
      if (t.id == id) return t;
    }
    return null;
  }

  int indexOfTier(String id) => tiers.indexWhere((t) => t.id == id);

  /// The list a character sits in: a tier's, or the unranked tray.
  List<int> _slotOf(int characterId) =>
      tierOf(characterId)?.characterIds ?? unranked;

  /// Adds [picked] to the unranked tray, skipping anyone already on the list
  /// and stopping at [maxCharacters]. Returns how many were added.
  int addCharacters(Iterable<TierCharacter> picked) {
    var added = 0;
    for (final c in picked) {
      if (isFull) break;
      if (characters.containsKey(c.id)) continue;
      characters[c.id] = c;
      unranked.add(c.id);
      added++;
    }
    if (added > 0) _touch();
    return added;
  }

  /// Moves [characterId] into the tier [toTierId] (null: the unranked tray)
  /// at [index], or to its end. Within one tier this reorders: [index] is
  /// where it should end up, counted after it has been taken out.
  /// Returns false when nothing could move.
  bool move(int characterId, {String? toTierId, int? index}) {
    if (!characters.containsKey(characterId)) return false;
    final List<int> to;
    if (toTierId == null) {
      to = unranked;
    } else {
      final t = tierById(toTierId);
      if (t == null) return false;
      to = t.characterIds;
    }
    final from = _slotOf(characterId);
    final oldIndex = from.indexOf(characterId);
    from.removeAt(oldIndex);
    final at = (index ?? to.length).clamp(0, to.length);
    to.insert(at, characterId);
    final moved = !identical(from, to) || oldIndex != at;
    if (moved) _touch();
    return moved;
  }

  /// One step along its tier (−1 left, +1 right). False at either end.
  bool nudge(int characterId, int step) {
    final slot = _slotOf(characterId);
    final i = slot.indexOf(characterId);
    final j = i + step;
    if (i < 0 || j < 0 || j >= slot.length) return false;
    slot
      ..removeAt(i)
      ..insert(j, characterId);
    _touch();
    return true;
  }

  /// One tier up (−1) or down (+1), keeping about the same place in the
  /// row. The unranked tray counts as the row below the bottom tier, as it
  /// sits on screen: down from the bottom tier sends a character there, and
  /// up from the tray lands them in the bottom tier. Up from the top tier,
  /// or down from the tray, does nothing.
  bool shift(int characterId, int step) {
    if (tiers.isEmpty || !characters.containsKey(characterId)) return false;
    final from = tierOf(characterId);
    final target = (from == null ? tiers.length : indexOfTier(from.id)) + step;
    if (target < 0 || target > tiers.length) return false;
    final at = _slotOf(characterId).indexOf(characterId);
    return move(characterId, toTierId: target == tiers.length ? null : tiers[target].id, index: at);
  }

  /// Takes [characterId] off the list altogether.
  bool remove(int characterId) {
    if (characters.remove(characterId) == null) return false;
    for (final t in tiers) {
      t.characterIds.remove(characterId);
    }
    unranked.remove(characterId);
    _touch();
    return true;
  }

  /// Sends every placed character back to the tray, keeping the tiers.
  void unrankAll() {
    for (final t in tiers) {
      unranked.addAll(t.characterIds);
      t.characterIds.clear();
    }
    _touch();
  }

  void renameTier(String tierId, String label) {
    final t = tierById(tierId);
    if (t == null) return;
    final clean = label.trim();
    final cut = clean.length > maxLabelLength
        ? clean.substring(0, maxLabelLength)
        : clean;
    if (t.label == cut) return;
    t.label = cut;
    _touch();
  }

  void setPigment(String tierId, int pigment) {
    final t = tierById(tierId);
    if (t == null || t.pigment == pigment) return;
    t.pigment = pigment;
    _touch();
  }

  /// Adds an empty tier below [afterTierId] (or at the bottom). Returns it,
  /// or null at [maxTiers].
  Tier? addTier({String? afterTierId, required String label, required int pigment}) {
    if (tiers.length >= maxTiers) return null;
    final tier = Tier(id: _freshTierId(), label: label, pigment: pigment);
    final at = afterTierId == null ? tiers.length : indexOfTier(afterTierId) + 1;
    tiers.insert(at.clamp(0, tiers.length), tier);
    _touch();
    return tier;
  }

  /// Deletes a tier; whoever was in it goes back to the tray, in order.
  /// The last tier can't be deleted.
  bool removeTier(String tierId) {
    if (tiers.length <= minTiers) return false;
    final i = indexOfTier(tierId);
    if (i < 0) return false;
    unranked.addAll(tiers[i].characterIds);
    tiers.removeAt(i);
    _touch();
    return true;
  }

  /// Moves a tier one row up (−1) or down (+1).
  bool moveTier(String tierId, int step) {
    final i = indexOfTier(tierId);
    final j = i + step;
    if (i < 0 || j < 0 || j >= tiers.length) return false;
    final t = tiers.removeAt(i);
    tiers.insert(j, t);
    _touch();
    return true;
  }

  /// The anime on this list, most-used first, each with its count. With
  /// [rankedOnly], only characters placed in a tier count: what the exported
  /// picture shows.
  List<MapEntry<int, int>> mediaByUse({bool rankedOnly = false}) {
    final counts = <int, int>{};
    final ids = rankedOnly ? [for (final t in tiers) ...t.characterIds] : characters.keys;
    for (final id in ids) {
      final m = characters[id]?.mediaId;
      if (m != null) counts[m] = (counts[m] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// A character who stands for [mediaId] on this list (for its cover,
  /// title and colour), or null.
  TierCharacter? sampleOf(int mediaId) {
    for (final c in characters.values) {
      if (c.mediaId == mediaId) return c;
    }
    return null;
  }

  String _freshTierId() {
    var n = tiers.length;
    while (tiers.any((t) => t.id == 't$n')) {
      n++;
    }
    return 't$n';
  }

  void _touch() => updatedAt = DateTime.now();

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'title': title,
        'prompt': prompt,
        'template': templateId,
        'tiers': [for (final t in tiers) t.toJson()],
        'unranked': unranked,
        'characters': [for (final c in characters.values) c.toJson()],
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  /// Reads a saved list. Anything inconsistent (a character in two places,
  /// an id with no character) is repaired rather than refused: a saved list
  /// is the user's work, and losing it is worse than tidying it.
  static TierList? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String) return null;
    final chars = <int, TierCharacter>{};
    for (final c in (json['characters'] as List?) ?? const []) {
      final tc = TierCharacter.fromJson(c);
      if (tc != null) chars[tc.id] = tc;
    }
    final tiers = <Tier>[
      for (final t in (json['tiers'] as List?) ?? const [])
        if (Tier.fromJson(t) case final Tier tier) tier,
    ];
    if (tiers.isEmpty) return null;
    final seen = <int>{};
    for (final t in tiers) {
      t.characterIds.retainWhere((c) => chars.containsKey(c) && seen.add(c));
    }
    final unranked = <int>[
      for (final c in (json['unranked'] as List?) ?? const [])
        if (c is int && chars.containsKey(c) && seen.add(c)) c,
    ];
    // Anyone with no place at all goes back to the tray.
    for (final c in chars.keys) {
      if (seen.add(c)) unranked.add(c);
    }
    DateTime at(Object? ms) => ms is int
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.fromMillisecondsSinceEpoch(0);
    return TierList(
      id: id,
      title: (json['title'] as String?) ?? 'Tier list',
      prompt: (json['prompt'] as String?) ?? '',
      templateId: (json['template'] as String?) ?? 'custom',
      tiers: tiers,
      unranked: unranked,
      characters: chars,
      createdAt: at(json['createdAt']),
      updatedAt: at(json['updatedAt']),
    );
  }
}
