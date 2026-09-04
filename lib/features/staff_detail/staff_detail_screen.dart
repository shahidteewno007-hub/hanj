import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../services/anilist_service.dart';
import '../../widgets/hover_anime_card.dart';
import '../../models/anime_model.dart';
import '../anime_detail/anime_detail_screen.dart';

class StaffDetailScreen extends StatefulWidget {
  final int staffId;
  final String staffName;

  const StaffDetailScreen({
    super.key,
    required this.staffId,
    required this.staffName,
  });

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  final _aniListService = AnilistService();
  Map<String, dynamic>? _staffData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStaffData();
  }

  Future<void> _loadStaffData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _aniListService.getStaffDetails(widget.staffId);
      setState(() {
        _staffData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _stripHtml(String? html) {
    if (html == null) return '';
    var text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</?[ib]>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    // Markdown links [text](url) to text
    text = text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1] ?? '');
    // Bold/italic markdown
    text = text.replaceAllMapped(RegExp(r'_{2}([^_]+)_{2}'), (m) => m[1] ?? '');
    text = text.replaceAllMapped(RegExp(r'\*{2}([^*]+)\*{2}'), (m) => m[1] ?? '');
    // Spoiler tags
    text = text.replaceAll(RegExp(r'~!|!~'), '');
    // Bare URLs
    text = text.replaceAll(RegExp(r'https?://\S+'), '');
    // Dollar placeholders like \$1
    text = text.replaceAll(RegExp(r'\\\$\d+'), '');
    // Source notes
    text = text.replaceAll(RegExp(r'\(Source:[^)]+\)', caseSensitive: false), '');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String? _calculateAge() {
    if (_staffData?['dateOfBirth'] == null) return null;
    
    final dob = _staffData!['dateOfBirth'];
    final year = dob['year'];
    final month = dob['month'];
    final day = dob['day'];
    
    if (year == null) return null;
    
    final now = DateTime.now();
    final birthDate = DateTime(
      year,
      month ?? 1,
      day ?? 1,
    );
    
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month || 
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    
    return age.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _staffData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: AppTheme.error),
                      const SizedBox(height: 16),
                      Text('Failed to load staff data',
                          style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // Header
                    SliverAppBar(
                      expandedHeight: 300,
                      pinned: true,
                      flexibleSpace: FlexibleSpaceBar(
                        background: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Background Image
                            if (_staffData!['image']?['large'] != null)
                              CachedNetworkImage(
                                imageUrl: _staffData!['image']['large'],
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  color: AppTheme.surfaceLight,
                                ),
                              ),
                            // Gradient Overlay
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    AppTheme.background.withValues(alpha: 0.8),
                                    AppTheme.background,
                                  ],
                                ),
                              ),
                            ),
                            // Name
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _staffData!['name']['full'] ?? 'Unknown',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                  ),
                                  if (_staffData!['name']['native'] != null)
                                    Text(
                                      _staffData!['name']['native'],
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: AppTheme.textSecondary,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Content
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Info cards row
                            Row(
                              children: [
                                if (_staffData!['dateOfBirth']?['year'] != null)
                                  Expanded(
                                    child: _InfoCard(
                                      icon: Icons.cake_rounded,
                                      label: 'Born',
                                      value: () {
                                        final dob = _staffData!['dateOfBirth'];
                                        final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                                        final parts = <String>[];
                                        if (dob['day'] != null) parts.add('${dob['day']}');
                                        if (dob['month'] != null) parts.add(months[(dob['month'] as int) - 1]);
                                        if (dob['year'] != null) parts.add('${dob['year']}');
                                        return parts.join(' ');
                                      }(),
                                    ),
                                  ),
                                if (_staffData!['dateOfBirth']?['year'] != null &&
                                    _staffData!['homeTown'] != null)
                                  const SizedBox(width: 8),
                                if (_staffData!['homeTown'] != null)
                                  Expanded(
                                    child: _InfoCard(
                                      icon: Icons.location_on_rounded,
                                      label: 'From',
                                      value: _staffData!['homeTown'].toString(),
                                    ),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Description
                            if (_staffData!['description'] != null &&
                                _staffData!['description'].toString().isNotEmpty) ...[
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('Biography',
                                      style: Theme.of(context).textTheme.titleLarge),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _SynopsisText(text: _stripHtml(_staffData!['description'])),
                              const SizedBox(height: 32),
                            ],

                            // Voice Acting Roles (shown first)
                            if (_staffData!['characterMedia']?['edges'] != null &&
                                (_staffData!['characterMedia']['edges'] as List)
                                    .isNotEmpty) ...[
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('Voice Acting Roles',
                                      style: Theme.of(context).textTheme.titleLarge),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildVoiceActingWorks(),
                              const SizedBox(height: 32),
                            ],

                            // Staff Roles (Director, Producer, etc.)
                            if (_staffData!['staffMedia']?['edges'] != null &&
                                (_staffData!['staffMedia']['edges'] as List).isNotEmpty) ...[
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: AppTheme.secondary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('Staff Roles',
                                      style: Theme.of(context).textTheme.titleLarge),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _buildStaffWorks(),
                              const SizedBox(height: 32),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStaffWorks() {
    final works = _staffData!['staffMedia']['edges'] as List;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: works.length,
      itemBuilder: (context, index) {
        final work = works[index];
        final anime = work['node'];
        final role = work['staffRole'] ?? 'Staff';
        
        return HoverAnimeCard(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AnimeDetailScreen(
                  anime: Anime(
                    id: anime['id'].toString(),
                    title: anime['title']['romaji'] ?? 'Unknown',
                    titleEnglish: anime['title']['english'],
                    imageUrl: anime['coverImage']['large'],
                    averageScore: anime['averageScore'] != null
                        ? (anime['averageScore'] as num).toDouble()
                        : null,
                    episodes: null,
                    status: null,
                    genres: [],
                    description: null,
                  ),
                ),
              ),
            );
          },
          glowColor: AppTheme.secondary,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: anime['coverImage']['large'],
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: AppTheme.surfaceLight,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            anime['title']['romaji'] ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.secondary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              role,
                              style: const TextStyle(
                                color: AppTheme.secondary,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceActingWorks() {
    final works = _staffData!['characterMedia']['edges'] as List;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: works.length,
      itemBuilder: (context, index) {
        final work = works[index];
        final anime = work['node'];
        final characterName = work['characterName'] ?? 'Unknown Character';
        
        return HoverAnimeCard(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AnimeDetailScreen(
                  anime: Anime(
                    id: anime['id'].toString(),
                    title: anime['title']['romaji'] ?? 'Unknown',
                    titleEnglish: anime['title']['english'],
                    imageUrl: anime['coverImage']['large'],
                    averageScore: anime['averageScore'] != null
                        ? (anime['averageScore'] as num).toDouble()
                        : null,
                    episodes: null,
                    status: null,
                    genres: [],
                    description: null,
                  ),
                ),
              ),
            );
          },
          glowColor: AppTheme.primary,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: anime['coverImage']['large'],
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      color: AppTheme.surfaceLight,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            anime['title']['romaji'] ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              characterName,
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(value,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SynopsisText extends StatefulWidget {
  final String text;
  const _SynopsisText({required this.text});

  @override
  State<_SynopsisText> createState() => _SynopsisTextState();
}

class _SynopsisTextState extends State<_SynopsisText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedCrossFade(
          firstChild: Text(widget.text, maxLines: 6, overflow: TextOverflow.ellipsis,
              style: AppTheme.sans(fontSize: 14, color: AppTheme.textSecondary, height: 1.7)),
          secondChild: Text(widget.text,
              style: AppTheme.sans(fontSize: 14, color: AppTheme.textSecondary, height: 1.7)),
          crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
        const SizedBox(height: 8),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? 'Show less' : 'Read more',
                style: AppTheme.sans(fontSize: 13, weight: FontWeight.w600, color: AppTheme.primary)),
          ),
        ),
      ],
    );
  }
}
