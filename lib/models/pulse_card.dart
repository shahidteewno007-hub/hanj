import 'package:flutter/foundation.dart';

enum PulseCardType {
  trailer,    // has a YouTube trailer to watch
  airingSoon, // next episode within 7 days
  nowAiring,  // currently airing this season (non-personalised)
  newSeason,  // announced sequel / continuation of something user watched
  upcoming,   // not yet released
}

@immutable
class PulseCard {
  final String id;
  final PulseCardType type;
  final String animeId;
  final String title;
  final String? imageUrl;
  final String headline;
  final String? reason; // personalisation line, e.g. "Because you watched Frieren"
  final DateTime timestamp;
  final Map<String, dynamic> payload; // type-specific extras

  const PulseCard({
    required this.id,
    required this.type,
    required this.animeId,
    required this.title,
    this.imageUrl,
    required this.headline,
    this.reason,
    required this.timestamp,
    this.payload = const {},
  });

  /// Stable deduplication key derived from (type, animeId, optional extra).
  static String makeId(PulseCardType type, String animeId, [String? extra]) =>
      '${type.name}_$animeId${extra != null ? '_$extra' : ''}';
}
