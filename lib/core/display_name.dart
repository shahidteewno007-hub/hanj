// ─────────────────────────────────────────────────────────────
// Display names (code batch 2, audit 7a item 8, LR-014)
//
// A name heads every post and reply in Arcs, so it has limits: at most 24
// characters, and none of a few words that would make it speak for Hanj
// ("Hanj", "admin", "moderator", "support" and the like) as a word of
// its own. firestore.rules runs the same test (hanjNameOk) on the user
// document and on Arcs' author names, so a name the app refuses the
// server refuses too. Uniqueness can wait (LR-014).
// ─────────────────────────────────────────────────────────────

class DisplayName {
  DisplayName._();

  /// Sign up and Edit Profile hold names to these limits. False gives back
  /// what they checked before (at least 3 characters on sign-up, not empty
  /// on Edit Profile). The rules hold them either way once deployed.
  static const bool enforced = true;

  /// The most characters a name may have. Counted as Unicode code points,
  /// as firestore.rules counts them.
  static const int max = 24;

  /// Words a name can't hold as a word of its own. Keep in step with
  /// hanjNameOk in firestore.rules.
  static const List<String> reserved = [
    'hanj',
    'admin',
    'administrator',
    'moderator',
    'mod',
    'support',
    'official',
    'staff',
  ];

  static final RegExp _reserved =
      RegExp('(^|[^a-z0-9])(${reserved.join('|')})([^a-z0-9]|\$)');

  /// How long [name] is, as the rules count it.
  static int length(String name) => name.runes.length;

  /// True when [name] holds a reserved word as a word of its own.
  static bool isReserved(String name) =>
      _reserved.hasMatch(name.toLowerCase());

  /// Why [name] can't be used, in words a field can show, or null when it
  /// can. [name] is checked as it will be saved, trimmed.
  static String? problem(String name) {
    final n = name.trim();
    if (length(n) > max) return 'Keep your name to $max characters or fewer.';
    if (isReserved(n)) return 'That name is kept for Hanj. Choose another.';
    return null;
  }

  /// [name] as it may be printed on a post: trimmed and cut to [max]; null
  /// when it's empty or holds a reserved word.
  static String? usable(String? name) {
    final n = name?.trim() ?? '';
    if (n.isEmpty) return null;
    final cut = length(n) > max
        ? String.fromCharCodes(n.runes.take(max)).trimRight()
        : n;
    if (cut.isEmpty || isReserved(cut)) return null;
    return cut;
  }
}
