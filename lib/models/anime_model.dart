class Anime {
  final String id;
  final String title;
  final String? titleEnglish;
  final String? imageUrl;
  final double? averageScore;
  final int? episodes;
  final String? status;
  final int? seasonYear;
  final String? season;
  final String? format;
  final List<String> genres;
  final String? description;
  final String? trailerUrl; // YouTube URL if available

  Anime({
    required this.id,
    required this.title,
    this.titleEnglish,
    this.imageUrl,
    this.averageScore,
    this.episodes,
    this.status,
    this.seasonYear,
    this.season,
    this.format,
    this.genres = const [],
    this.description,
    this.trailerUrl,
  });

  factory Anime.fromJson(Map<String, dynamic> json) {
    return Anime(
      id: json['id'].toString(),
      title: json['title'] as String? ?? 'Unknown',
      titleEnglish: json['titleEnglish'] as String?,
      imageUrl: json['imageUrl'] as String?,
      averageScore: json['averageScore'] != null
          ? (json['averageScore'] as num).toDouble()
          : null,
      episodes: json['episodes'] is int
          ? json['episodes'] as int
          : (json['episodes'] is String
              ? int.tryParse(json['episodes'] as String)
              : null),
      status: json['status'] as String?,
      seasonYear: json['seasonYear'] as int?,
      season: json['season'] as String?,
      format: json['format'] as String?,
      genres: json['genres'] != null
          ? List<String>.from(json['genres'] as List)
          : [],
      description: json['description'] as String?,
      trailerUrl: json['trailerUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'titleEnglish': titleEnglish,
      'imageUrl': imageUrl,
      'averageScore': averageScore,
      'episodes': episodes,
      'status': status,
      'seasonYear': seasonYear,
      'season': season,
      'format': format,
      'genres': genres,
      'description': description,
      'trailerUrl': trailerUrl,
    };
  }
}
