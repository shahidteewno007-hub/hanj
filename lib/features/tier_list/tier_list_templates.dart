// Tier lists: the templates a list can start from, and the tier names the
// rename sheet suggests.
//
// Drawn from what anime fans rank and how they name tiers (research of
// 2026-11-03: 330 TierMaker anime templates, the VS Battles tiering page,
// each show's own ranks, YouTube's tier-list videos; sources in the round
// seven report, r7-tierlists-report.md). In short:
//  - most fan lists rank one show's whole cast, so "Rank the cast" leads;
//  - most keep five rows, S to D, adding a row above S, rows below D, a
//    "Who?" row for the ones they haven't seen, or "Trash" at the bottom;
//  - power lists borrow the VS Battles names ("Universe level", "Planet
//    level"), or a show's own ranks (One Punch Man's threat levels, Jujutsu
//    Kaisen's grades);
//  - the newer slang (Peak, Goated, Mid, Fraud, Absolute Cinema) is real but
//    rarer as a label than as a video title.
// Every tier name stays editable, and "Blank" starts with unnamed tiers.
// Items are characters, so lists of openings, fights or seasons (also
// popular) aren't templates here.
import 'package:flutter/material.dart';

import 'tier_list_model.dart';
import 'tier_list_widgets.dart';

/// What a template ranks by, for grouping on the start screen.
enum TierTemplateKind {
  /// Plain tiers, or one show's cast.
  starter('Start here'),

  /// Who would win: power-scaling tiers.
  power('Power scaling'),

  /// Taste and hot takes: community tiers.
  opinion('Hot takes'),

  /// A show's own ranks, reused as tiers.
  show('Ranked like the show');

  const TierTemplateKind(this.heading);
  final String heading;
}

class TierListTemplate {
  const TierListTemplate({
    required this.id,
    required this.name,
    required this.prompt,
    required this.kind,
    required this.tiers,
    required this.icon,
    this.pigments,
    this.title,
    this.characters = const [],
    this.anime = const [],
  });

  final String id;

  /// The template's name on the start screen ("Strongest MC").
  final String name;

  /// The question the list answers, shown under its title.
  final String prompt;
  final TierTemplateKind kind;

  /// Tier names, top first. An empty name is an unnamed tier.
  final List<String> tiers;

  /// Indexes into [TierPigment.all], one per tier; a ramp when null.
  final List<int>? pigments;
  final IconData icon;

  /// The new list's title; [name] when null.
  final String? title;

  /// Characters and anime worth searching first, offered as chips in the
  /// picker before anything is typed.
  final List<String> characters;
  final List<String> anime;

  List<int> get pigmentsOrRamp => pigments ?? TierPigment.ramp(tiers.length);

  /// A fresh, empty list from this template.
  TierList create({required String id, DateTime? now}) {
    final at = now ?? DateTime.now();
    final p = pigmentsOrRamp;
    return TierList(
      id: id,
      title: title ?? name,
      prompt: prompt,
      templateId: this.id,
      tiers: [
        for (var i = 0; i < tiers.length; i++)
          Tier(id: 't$i', label: tiers[i], pigment: i < p.length ? p[i] : TierPigment.all.length - 1),
      ],
      createdAt: at,
    );
  }
}

/// The template with [id], or null (a list made before a template was
/// renamed still opens; it just has no template behind it).
TierListTemplate? tierTemplateById(String id) {
  for (final t in kTierTemplates) {
    if (t.id == id) return t;
  }
  if (TierListSwitches.gauntlet && id == kGauntletTemplate.id) return kGauntletTemplate;
  return null;
}

/// Round nine: the Gauntlet. One challenger against five opponents, one
/// phase after another, each harder: how far do they go? People post these
/// as questions ("How far does Naruto get?") and answer them in the
/// replies. The first tier holds the challenger and each phase one
/// opponent; `TierList.verdict` keeps where the challenger falls, if the
/// list says. tier_list_gauntlet.dart draws the board and the picture.
/// It isn't in [kTierTemplates]: it has its own card on the start screen.
const kGauntletTemplate = TierListTemplate(
  id: 'gauntlet',
  name: 'Gauntlet',
  title: 'Gauntlet',
  prompt: 'Five fights in a row, each one harder.',
  kind: TierTemplateKind.power,
  tiers: ['Challenger', 'Phase 1', 'Phase 2', 'Phase 3', 'Phase 4', 'Phase 5'],
  // Gold for the challenger; the phases warm from bamboo to peony as they
  // get harder.
  pigments: [_gold, _bamboo, _teal, _sky, _wisteria, _peony],
  icon: Icons.sports_mma_rounded,
  // Round seven checked each name against the picker's own AniList search.
  characters: [
    'Naruto Uzumaki', 'Monkey D. Luffy', 'Gojo Satoru', 'Goku', 'Saitama',
    'Sukuna', 'Madara Uchiha', 'Levi', 'Roronoa Zoro', 'Meruem',
  ],
);

// Pigment indexes (TierPigment.all), for templates whose floor is a
// "who?" or "trash" row rather than the next colour down.
const _gold = 0, _peony = 1, _wisteria = 2, _sky = 3, _teal = 4, _bamboo = 5, _moss = 6;
const _ash = 7, _ink = 8;

const _popularShows = [
  'Jujutsu Kaisen', 'Naruto', 'Hunter x Hunter', 'Demon Slayer', 'One Piece',
  'Haikyuu!!', 'My Hero Academia', 'JoJo’s Bizarre Adventure', 'Bleach', 'Frieren',
];

const kTierTemplates = <TierListTemplate>[
  // ── Start here ───────────────────────────────────────────
  TierListTemplate(
    id: 'cast',
    name: 'Rank the cast',
    title: 'The cast, ranked',
    prompt: 'Pick one show and rank its whole cast.',
    kind: TierTemplateKind.starter,
    tiers: ['S', 'A', 'B', 'C', 'D', 'Who?'],
    pigments: [_gold, _peony, _wisteria, _sky, _teal, _ink],
    icon: Icons.groups_rounded,
    anime: _popularShows,
  ),
  TierListTemplate(
    id: 'classic',
    name: 'Classic S to F',
    title: 'My tier list',
    prompt: 'Rank them, the classic way.',
    kind: TierTemplateKind.starter,
    tiers: ['S', 'A', 'B', 'C', 'D', 'F'],
    icon: Icons.format_list_numbered_rounded,
  ),
  TierListTemplate(
    id: 'god-tier',
    name: 'God tier to trash',
    title: 'God tier to trash',
    prompt: 'From god tier all the way down.',
    kind: TierTemplateKind.starter,
    tiers: ['God tier', 'Top tier', 'High tier', 'Mid tier', 'Low tier', 'Trash'],
    pigments: [_gold, _peony, _wisteria, _sky, _ash, _ink],
    icon: Icons.workspace_premium_rounded,
  ),
  TierListTemplate(
    id: 'vibes',
    name: 'Vibe check',
    title: 'Vibe check',
    prompt: 'How do you really feel about them?',
    kind: TierTemplateKind.starter,
    tiers: ['Peak', 'Goated', 'Solid', 'Mid', 'Trash', 'Who?'],
    pigments: [_gold, _peony, _teal, _ash, _ink, _ink],
    icon: Icons.local_fire_department_rounded,
  ),
  TierListTemplate(
    id: 'blank',
    name: 'Make your own',
    title: 'Untitled tier list',
    prompt: 'Start blank and name your own tiers.',
    kind: TierTemplateKind.starter,
    tiers: ['', '', '', '', ''],
    icon: Icons.edit_rounded,
  ),

  // ── Power scaling ────────────────────────────────────────
  TierListTemplate(
    id: 'strongest-mc',
    name: 'Strongest MC',
    title: 'Strongest MCs',
    prompt: 'Who is the strongest protagonist in anime?',
    kind: TierTemplateKind.power,
    // VS Battles' own names, strongest first.
    tiers: [
      'Multiverse level', 'Universe level', 'Galaxy level', 'Planet level',
      'Country level', 'City level', 'Street level',
    ],
    icon: Icons.bolt_rounded,
    characters: ['Saitama', 'Goku', 'Gojo Satoru', 'Monkey D. Luffy', 'Naruto Uzumaki', 'Anos Voldigoad', 'Rimuru Tempest', 'Yuuji Itadori'],
  ),
  TierListTemplate(
    id: 'strongest-overall',
    name: 'Strongest overall',
    title: 'The strongest in anime',
    prompt: 'Who is the strongest character in anime?',
    kind: TierTemplateKind.power,
    tiers: [
      'Omnipotent', 'Universal threat', 'Planet buster', 'Powered human',
      'Peak human', 'Average human', 'Weakling',
    ],
    icon: Icons.public_rounded,
    characters: ['Madoka Kaname', 'Anos Voldigoad', 'Saitama', 'Sukuna', 'Escanor', 'Yuujirou Hanma', 'Levi'],
  ),
  TierListTemplate(
    id: 'villain-threat',
    name: 'Villain threat',
    title: 'Villain threat levels',
    prompt: 'Which villain is the biggest threat? Rate them like the Hero Association.',
    kind: TierTemplateKind.power,
    // One Punch Man's disaster levels.
    tiers: ['God', 'Dragon', 'Demon', 'Tiger', 'Wolf'],
    pigments: [_gold, _peony, _wisteria, _sky, _ash],
    icon: Icons.warning_amber_rounded,
    characters: ['Sukuna', 'Madara Uchiha', 'Frieza', 'Muzan Kibutsuji', 'Sousuke Aizen', 'Meruem', 'Boros'],
  ),
  TierListTemplate(
    id: 'swordsman',
    name: 'Best swordsman',
    title: 'Best swordsmen',
    prompt: 'Who is the best blade in anime?',
    kind: TierTemplateKind.power,
    tiers: ['Absolute master', 'Top tier', 'Pretty good', 'Some experience', 'Guy with a sword'],
    pigments: [_gold, _peony, _sky, _teal, _ash],
    icon: Icons.content_cut_rounded,
    characters: ['Roronoa Zoro', 'Dracule Mihawk', 'Kenpachi Zaraki', 'Yoriichi Tsugikuni', 'Guts', 'Himura Kenshin'],
  ),
  TierListTemplate(
    id: 'fraud-watch',
    name: 'Fraud watch',
    title: 'Fraud watch',
    prompt: 'Who lived up to the hype, and who is a fraud?',
    kind: TierTemplateKind.power,
    tiers: ['Lived up to it', 'Legit', 'Mid', 'Fraud', 'Jobber'],
    pigments: [_gold, _bamboo, _ash, _wisteria, _ink],
    icon: Icons.sentiment_dissatisfied_rounded,
    characters: ['Yamcha', 'Hisoka', 'Sousuke Aizen', 'Tengen Uzui', 'Endeavor', 'Madara Uchiha'],
  ),

  // ── Hot takes ────────────────────────────────────────────
  TierListTemplate(
    id: 'best-villain',
    name: 'Best villain',
    title: 'Best villains',
    prompt: 'Which villain is written best? Writing, not power.',
    kind: TierTemplateKind.opinion,
    tiers: ['Absolute Cinema', 'Peak fiction', 'Great', 'Solid', 'Mid', 'Forgettable'],
    pigments: [_gold, _peony, _wisteria, _sky, _ash, _ink],
    icon: Icons.theater_comedy_rounded,
    characters: ['Johan Liebert', 'Griffith', 'Light Yagami', 'Meruem', 'Pain', 'Sukuna', 'Dio Brando'],
  ),
  TierListTemplate(
    id: 'most-aura',
    name: 'Most aura',
    title: 'Most aura',
    prompt: 'Who has the most aura?',
    kind: TierTemplateKind.opinion,
    tiers: ['The chosen ones', 'Aura farmers', 'Sleeper build', 'Aura NPC', 'Aura debtors'],
    pigments: [_gold, _wisteria, _teal, _ash, _ink],
    icon: Icons.auto_awesome_rounded,
    characters: ['Gojo Satoru', 'Itachi Uchiha', 'Sousuke Aizen', 'Levi', 'Shanks', 'Yoriichi Tsugikuni'],
  ),
  TierListTemplate(
    id: 'best-sensei',
    name: 'Best sensei',
    title: 'Best senseis',
    prompt: 'Who is the best sensei or mentor?',
    kind: TierTemplateKind.opinion,
    tiers: ['Greatest', 'Great mentor', 'Solid', 'Questionable', 'Worst'],
    pigments: [_gold, _bamboo, _sky, _ash, _ink],
    icon: Icons.school_rounded,
    characters: ['Kakashi Hatake', 'Gojo Satoru', 'Koro-sensei', 'Jiraiya', 'All Might', 'Sakonji Urokodaki', 'Master Roshi'],
  ),
  TierListTemplate(
    id: 'anime-dads',
    name: 'Anime dads',
    title: 'Best and worst anime dads',
    prompt: 'Best and worst dads in anime?',
    kind: TierTemplateKind.opinion,
    tiers: [
      'I wish he was my dad', 'A good dad', 'A dad', 'A bad dad',
      'Call the authorities', 'Bury him under the jail',
    ],
    pigments: [_gold, _bamboo, _sky, _wisteria, _ash, _ink],
    icon: Icons.family_restroom_rounded,
    characters: ['Loid Forger', 'Minato Namikaze', 'Van Hohenheim', 'Endeavor', 'Gendou Ikari', 'Ging Freecss', 'Shou Tucker'],
  ),
  TierListTemplate(
    id: 'tragic',
    name: 'Saddest backstory',
    title: 'Saddest backstories',
    prompt: 'Whose backstory or death hit hardest?',
    kind: TierTemplateKind.opinion,
    tiers: ['Incredibly tragic', 'Very tragic', 'Tragic', 'Sad', 'Kinda sad', 'Not even sad'],
    pigments: [_sky, _wisteria, _teal, _bamboo, _ash, _ink],
    icon: Icons.water_drop_rounded,
    characters: ['Gaara', 'Pain', 'Kyoujurou Rengoku', 'Jiraiya', 'Itachi Uchiha', 'Nina Tucker', 'Ken Kaneki'],
  ),
  TierListTemplate(
    id: 'smartest',
    name: 'Smartest minds',
    title: 'Smartest characters',
    prompt: 'Who is the smartest character in anime?',
    kind: TierTemplateKind.opinion,
    tiers: ['GOAT', 'SS', 'S', 'A', 'B', 'C', 'D'],
    icon: Icons.psychology_rounded,
    characters: ['Lelouch Lamperouge', 'Light Yagami', 'L', 'Senkuu Ishigami', 'Shikamaru Nara', 'Kiyotaka Ayanokouji', 'Johan Liebert'],
  ),
  TierListTemplate(
    id: 'best-girl',
    name: 'Best girl',
    title: 'Best girl',
    prompt: 'Who is best girl? Settle it.',
    kind: TierTemplateKind.opinion,
    tiers: ['Best girl', 'S', 'A', 'B', 'C', 'D'],
    icon: Icons.favorite_rounded,
    anime: ['Spy x Family', 'Frieren', 'Re:Zero', 'Kaguya-sama: Love is War', 'Chainsaw Man'],
  ),
  TierListTemplate(
    id: 'best-boy',
    name: 'Best boy',
    title: 'Best boy',
    prompt: 'Who is best boy? Settle it.',
    kind: TierTemplateKind.opinion,
    tiers: ['Best boy', 'S', 'A', 'B', 'C', 'D'],
    pigments: [_gold, _sky, _teal, _bamboo, _moss, _ash],
    icon: Icons.star_rounded,
    anime: ['Haikyuu!!', 'Jujutsu Kaisen', 'Attack on Titan', 'Hunter x Hunter', 'Bungo Stray Dogs'],
  ),
  TierListTemplate(
    id: 'side-characters',
    name: 'Side characters',
    title: 'Best side characters',
    prompt: 'Which side character outshines the MC?',
    kind: TierTemplateKind.opinion,
    tiers: ['Goated', 'A', 'B', 'C', 'D'],
    icon: Icons.person_search_rounded,
    characters: ['Kakashi Hatake', 'Zenitsu Agatsuma', 'Killua Zoldyck', 'Toji Fushiguro', 'Rock Lee', 'Reigen Arataka'],
  ),

  // ── Ranked like the show ─────────────────────────────────
  TierListTemplate(
    id: 'sorcerer-grade',
    name: 'Sorcerer grade',
    title: 'Sorcerer grades',
    prompt: 'What grade would they be?',
    kind: TierTemplateKind.show,
    tiers: ['Special Grade', 'Grade 1', 'Semi-Grade 1', 'Grade 2', 'Semi-Grade 2', 'Grade 3', 'Grade 4'],
    icon: Icons.local_fire_department_outlined,
    anime: ['Jujutsu Kaisen', 'Jujutsu Kaisen 0'],
  ),
  TierListTemplate(
    id: 'hero-class',
    name: 'Hero class',
    title: 'Hero classes',
    prompt: 'Which Hero Association class would they earn?',
    kind: TierTemplateKind.show,
    tiers: ['S-Class', 'A-Class', 'B-Class', 'C-Class'],
    icon: Icons.shield_rounded,
    anime: ['One Punch Man'],
  ),
  TierListTemplate(
    id: 'ninja-rank',
    name: 'Ninja rank',
    title: 'Ninja ranks',
    prompt: 'What rank would they hold in the Leaf?',
    kind: TierTemplateKind.show,
    tiers: ['Kage', 'Jonin', 'Chunin', 'Genin', 'Academy Student'],
    pigments: [_gold, _peony, _sky, _teal, _ash],
    icon: Icons.whatshot_outlined,
    anime: ['Naruto', 'Naruto: Shippuden', 'Boruto'],
  ),
  TierListTemplate(
    id: 'grand-line',
    name: 'Grand Line rank',
    title: 'Grand Line ranks',
    prompt: 'Who is Emperor-level, and who is fodder?',
    kind: TierTemplateKind.show,
    tiers: ['Yonko', 'Admiral', 'Warlord', 'Supernova', 'Fodder'],
    pigments: [_gold, _sky, _wisteria, _teal, _ink],
    icon: Icons.sailing_rounded,
    anime: ['One Piece'],
  ),
  TierListTemplate(
    id: 'hunter-rank',
    name: 'Hunter rank',
    title: 'Hunter ranks',
    prompt: 'If they awakened as a Hunter, what rank would they get?',
    kind: TierTemplateKind.show,
    tiers: ['National Level', 'S-Rank', 'A-Rank', 'B-Rank', 'C-Rank', 'D-Rank', 'E-Rank'],
    icon: Icons.military_tech_rounded,
    anime: ['Solo Leveling'],
  ),
];

/// Tier names the rename sheet offers, by scheme, top tier first.
const kTierNameSchemes = <String, List<String>>{
  'Classic': ['SSS', 'SS', 'S+', 'S', 'A', 'B', 'C', 'D', 'E', 'F', 'Z'],
  'Community': [
    'GOAT', 'Absolute Cinema', 'Peak', 'Peak fiction', 'Masterpiece', 'Goated',
    'Solid', 'Mid', 'Fraud', 'Jobber', 'Fodder', 'Trash', 'Who?', 'Haven’t watched',
  ],
  'God tier': ['God tier', 'Top tier', 'High tier', 'Mid tier', 'Low tier', 'Trash'],
  // VS Battles' official names (vsbattles.fandom.com/wiki/Tiering_System).
  'VS Battles': [
    'Boundless', 'Outerverse level', 'Multiverse level', 'Universe level',
    'Galaxy level', 'Star level', 'Planet level', 'Moon level', 'Continent level',
    'Country level', 'Island level', 'Mountain level', 'City level', 'Town level',
    'Building level', 'Wall level', 'Street level', 'Athlete level', 'Human level',
  ],
  // How fans shorten them on TierMaker.
  'Fan power scale': [
    'Omnipotent', 'Outerversal', 'Multiversal', 'Universal', 'Galaxy',
    'Planetary', 'Country', 'City', 'Normal',
  ],
  'Threat level': ['God', 'Dragon', 'Demon', 'Tiger', 'Wolf'],
  'Hero class': ['S-Class', 'A-Class', 'B-Class', 'C-Class'],
  'Sorcerer grade': [
    'The Strongest', 'Special Grade', 'Grade 1', 'Semi-Grade 1', 'Grade 2',
    'Semi-Grade 2', 'Grade 3', 'Grade 4',
  ],
  'Ninja rank': ['Kage', 'Jonin', 'Chunin', 'Genin', 'Academy Student'],
  'One Piece': ['Pirate King', 'Yonko', 'Admiral', 'Warlord', 'Supernova', 'Fodder'],
  'Demon Slayer': ['Hashira', 'Upper Rank', 'Lower Rank'],
  'Hunter rank': ['National Level', 'S-Rank', 'A-Rank', 'B-Rank', 'C-Rank', 'D-Rank', 'E-Rank'],
  'Hunter stars': ['Triple-Star', 'Double-Star', 'Single-Star'],
  'Dragon Ball': ['Omni-King', 'God of Destruction', 'Angel', 'Z'],
};

/// The schemes worth offering first for a template: its own tiers, then the
/// rest.
List<MapEntry<String, List<String>>> tierNameSuggestionsFor(String templateId) {
  final t = tierTemplateById(templateId);
  final out = <MapEntry<String, List<String>>>[];
  if (t != null && t.tiers.any((l) => l.isNotEmpty)) {
    out.add(MapEntry('From this template', [for (final l in t.tiers) if (l.isNotEmpty) l]));
  }
  out.addAll(kTierNameSchemes.entries);
  return out;
}
