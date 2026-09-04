import 'cadre_rankings.dart';

/// Hand-assigned role fit, for anime where a character is obviously built for
/// one seat and obviously wrong for another.
///
/// [CadreRankings] answers "how strong is this character". This answers "what
/// is this character *for*", which is the question Squad is actually about.
/// Without it a draft is a sorting exercise: every slot multiplier is 1.0, so
/// the best play is always the biggest number in the highest open weight and
/// the only real decision left is when to hold out.
///
/// **Archetypes, not loose numbers.** Writing five doubles per character by
/// hand invites drift — the twentieth character gets judged against a
/// half-remembered version of the third. Each character is tagged with one of
/// seven archetypes instead, so adding one is a single word and every
/// character sharing a shape shares its numbers exactly.
///
/// **Every archetype sums to 5.00**, which is a rule and not a coincidence.
/// Affinity multiplies power, and a character carrying no affinity data sits
/// at a flat 1.0 in all five slots — total 5.00. Holding listed characters to
/// the same total means being in this table is never a blanket buff or a
/// blanket tax: it redistributes a character's strength across the slots
/// rather than adding or removing any. A partly covered cast stays internally
/// fair, the same way a partly ranked one does.
///
/// The upside of being listed is earned at placement. A character with real
/// affinity peaks higher than 1.0 in the seat they belong in, so knowing what
/// someone is for pays off only if you put them there.
///
/// **Matching is exact, not fuzzy** — same rule and same [CadreRankings.normalise]
/// as the power table, so the two can never disagree about how a name is
/// spelled. Every spelling AniList might print needs its own key.
///
/// Adding an anime here is pure data. Anything unlisted keeps flat affinity
/// and plays exactly as it does today, so this can only add depth to a cast
/// and never break one.
class CadreAffinity {
  const CadreAffinity._();

  // ---------------------------------------------------------------------
  // Archetypes. Slot order throughout: captain, vice, tank, healer, support.
  // ---------------------------------------------------------------------

  /// Leads from the front and is diminished anywhere else.
  static const Map<String, double> commander = <String, double>{
    'captain': 1.30,
    'vice': 1.15,
    'tank': 0.95,
    'healer': 0.75,
    'support': 0.85,
  };

  /// The right hand. Strong everywhere, best one seat down from the top.
  static const Map<String, double> vanguard = <String, double>{
    'captain': 1.05,
    'vice': 1.30,
    'tank': 1.05,
    'healer': 0.75,
    'support': 0.85,
  };

  /// Fights, and only fights. Put them in charge of people at your peril.
  static const Map<String, double> duelist = <String, double>{
    'captain': 1.10,
    'vice': 1.05,
    'tank': 1.25,
    'healer': 0.65,
    'support': 0.95,
  };

  /// Absorbs what the squad cannot. The clearest single-slot specialist.
  static const Map<String, double> bulwark = <String, double>{
    'captain': 0.85,
    'vice': 0.95,
    'tank': 1.45,
    'healer': 0.90,
    'support': 0.85,
  };

  /// Plans, reads, advises. Wasted holding a line, useless holding a bandage.
  static const Map<String, double> strategist = <String, double>{
    'captain': 0.95,
    'vice': 1.40,
    'tank': 0.80,
    'healer': 0.75,
    'support': 1.10,
  };

  /// Keeps everyone standing. The steepest fall-off of any archetype.
  static const Map<String, double> medic = <String, double>{
    'captain': 0.70,
    'vice': 0.85,
    'tank': 0.80,
    'healer': 1.50,
    'support': 1.15,
  };

  /// Tools, transport, supply, cover fire. Unglamorous and load-bearing.
  static const Map<String, double> quartermaster = <String, double>{
    'captain': 0.75,
    'vice': 0.90,
    'tank': 0.95,
    'healer': 1.10,
    'support': 1.30,
  };

  // ---------------------------------------------------------------------
  // Casts
  // ---------------------------------------------------------------------

  static const Map<String, Map<String, double>> _onePiece =
      <String, Map<String, double>>{
    'goldroger': commander,
    'golderoger': commander,
    'edwardnewgate': commander,
    'whitebeard': commander,
    'shanks': commander,
    'monkeydluffy': commander,
    'luffy': commander,
    'marshalldteach': commander,
    'blackbeard': commander,
    'donquixotedoflamingo': commander,
    'doflamingo': commander,
    'boahancock': commander,
    // Runs a crew of one and still ends up a Yonko. The joke works because
    // the numbers back it: a 45 in Captain is still a Captain.
    'buggy': commander,

    'silversrayleigh': vanguard,
    'rayleigh': vanguard,
    'roronoazoro': vanguard,
    'zoro': vanguard,
    'vinsmokesanji': vanguard,
    'sanji': vanguard,
    'portgasdace': vanguard,
    'sabo': vanguard,
    'koby': vanguard,
    'coby': vanguard,

    'draculemihawk': duelist,
    'mihawk': duelist,
    'monkeydgarp': duelist,
    'garp': duelist,
    'sakazuki': duelist,
    'akainu': duelist,
    'borsalino': duelist,
    'kizaru': duelist,
    'kuzan': duelist,
    'aokiji': duelist,
    'roblucci': duelist,
    'enel': duelist,
    'eneru': duelist,
    'smoker': duelist,

    'kaido': bulwark,
    'kaidou': bulwark,
    'charlottelinlin': bulwark,
    'bigmom': bulwark,
    'charlottekatakuri': bulwark,
    'katakuri': bulwark,
    'yamato': bulwark,
    'bartholomewkuma': bulwark,
    'magellan': bulwark,
    'vergo': bulwark,
    'jinbe': bulwark,
    'jinbei': bulwark,
    'jimbei': bulwark,

    'sengoku': strategist,
    'crocodile': strategist,
    'nicorobin': strategist,
    'nami': strategist,

    // Surgeon of Death, and a Phoenix whose flames heal. Both are top-tier
    // fighters who are worth more patching the squad up than leading it.
    'trafalgardwaterlaw': medic,
    'trafalgarlaw': medic,
    'marco': medic,
    'tonytonychopper': medic,
    'chopper': medic,

    'brook': quartermaster,
    'franky': quartermaster,
    'usopp': quartermaster,
  };

  static const Map<String, Map<String, double>> _naruto =
      <String, Map<String, double>>{
    'kaguyaootsutsuki': commander,
    'kaguyaotsutsuki': commander,
    'hagoromoootsutsuki': commander,
    'hagoromootsutsuki': commander,
    'madarauchiha': commander,
    'hashiramasenju': commander,
    'narutouzumaki': commander,
    'minatonamikaze': commander,
    'nagato': commander,
    'pain': commander,

    'kakashihatake': vanguard,
    'hatakekakashi': vanguard,
    'killerbee': vanguard,
    'konohamarusarutobi': vanguard,

    'sasukeuchiha': duelist,
    'obitouchiha': duelist,
    'mightguy': duelist,
    'maitogai': duelist,
    'deidara': duelist,
    'nejihyuuga': duelist,
    'nejihyuga': duelist,
    'rocklee': duelist,
    'kibainuzuka': duelist,
    'zabuzamomochi': duelist,

    'gaara': bulwark,
    'kisamehoshigaki': bulwark,
    'kakuzu': bulwark,
    'hidan': bulwark,
    'choujiakimichi': bulwark,
    'chojiakimichi': bulwark,

    'itachiuchiha': strategist,
    'tobiramasenju': strategist,
    'orochimaru': strategist,
    'jiraiya': strategist,
    'sasori': strategist,
    'inoyamanaka': strategist,
    // The one this whole table exists for: 1.40 in Vice, 0.75 in Healer.
    'shikamarunara': strategist,

    'tsunade': medic,
    'kabutoyakushi': medic,
    'sakuraharuno': medic,
    'haku': medic,

    'konan': quartermaster,
    'tenten': quartermaster,
    'shinoaburame': quartermaster,
    'hinatahyuuga': quartermaster,
    'hinatahyuga': quartermaster,
    'irukaumino': quartermaster,
  };

  /// Affinity tables by normalised anime title.
  ///
  /// Deliberately narrower than [CadreRankings]: power can be judged for any
  /// character at a glance, but role fit needs someone who knows what the
  /// character actually does. Seven more casts are ranked for power and
  /// unlisted here, and they play exactly as they did before.
  static const Map<String, Map<String, Map<String, double>>> _byTitle =
      <String, Map<String, Map<String, double>>>{
    'onepiece': _onePiece,

    'naruto': _naruto,
    'narutoshippuden': _naruto,
    'narutoshippuuden': _naruto,
  };

  /// Affinity for an anime, or null when it isn't covered.
  static Map<String, Map<String, double>>? forTitle(String title) =>
      _byTitle[CadreRankings.normalise(title)];

  /// True when this anime has an affinity table at all.
  static bool covers(String title) =>
      _byTitle.containsKey(CadreRankings.normalise(title));

  /// Titles carrying role fit. Handy for a debug screen.
  static Iterable<String> get titles => _byTitle.keys;
}
