/// A player's Cadre record.
class CadreStats {
  final int played;
  final int won;
  final int lost;
  final int drawn;
  final int cardsTaken;
  final int currentStreak;
  final int bestStreak;
  final String? lastPool;

  const CadreStats({
    this.played = 0,
    this.won = 0,
    this.lost = 0,
    this.drawn = 0,
    this.cardsTaken = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastPool,
  });

  static const empty = CadreStats();

  /// 0.0 to 1.0. Draws count against you the same way a loss doesn't.
  double get winRate => played == 0 ? 0 : won / played;

  bool get hasRecord => played > 0;

  /// Returns a new record with this result folded in.
  ///
  /// Only bot matches should be recorded \u2014 pass-and-play has two people on
  /// one device and there is no honest way to say whose record it is.
  CadreStats recording({
    required bool win,
    required bool loss,
    required int cards,
    required String pool,
  }) {
    final streak = win ? currentStreak + 1 : 0;
    return CadreStats(
      played: played + 1,
      won: won + (win ? 1 : 0),
      lost: lost + (loss ? 1 : 0),
      drawn: drawn + (!win && !loss ? 1 : 0),
      cardsTaken: cardsTaken + cards,
      currentStreak: streak,
      bestStreak: streak > bestStreak ? streak : bestStreak,
      lastPool: pool,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'played': played,
        'won': won,
        'lost': lost,
        'drawn': drawn,
        'cardsTaken': cardsTaken,
        'currentStreak': currentStreak,
        'bestStreak': bestStreak,
        'lastPool': lastPool,
      };

  factory CadreStats.fromJson(Map<String, dynamic> json) => CadreStats(
        played: (json['played'] as num?)?.toInt() ?? 0,
        won: (json['won'] as num?)?.toInt() ?? 0,
        lost: (json['lost'] as num?)?.toInt() ?? 0,
        drawn: (json['drawn'] as num?)?.toInt() ?? 0,
        cardsTaken: (json['cardsTaken'] as num?)?.toInt() ?? 0,
        currentStreak: (json['currentStreak'] as num?)?.toInt() ?? 0,
        bestStreak: (json['bestStreak'] as num?)?.toInt() ?? 0,
        lastPool: json['lastPool'] as String?,
      );
}
