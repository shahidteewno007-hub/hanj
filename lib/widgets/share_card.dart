import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'gal_mobile.dart' if (dart.library.html) 'gal_stub.dart' as galSaver;

import '../core/theme/app_theme.dart';
import '../models/anime_model.dart';

/// Shows the share card modal bottom sheet.
void showShareCard(
  BuildContext context, {
  required Anime anime,
  String? status,
  double? userRating,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => ShareCardSheet(
      anime: anime,
      status: status,
      userRating: userRating,
    ),
  );
}

class ShareCardSheet extends StatefulWidget {
  final Anime anime;
  final String? status;
  final double? userRating;

  const ShareCardSheet({
    super.key,
    required this.anime,
    this.status,
    this.userRating,
  });

  @override
  State<ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<ShareCardSheet> {
  final _repaintKey = GlobalKey();
  bool _isCapturing = false;

  Future<void> _downloadCard() async {
    setState(() => _isCapturing = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();

      if (kIsWeb) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Right-click the card to save on web'),
              backgroundColor: Color(0xFF4CAF50),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        await galSaver.saveImageToGallery(bytes, 'hanj_share_${DateTime.now().millisecondsSinceEpoch}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Card saved to gallery!'),
              backgroundColor: Color(0xFF4CAF50),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save card.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF130B22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Share Card',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Save and share your anime card',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 24),

          RepaintBoundary(
            key: _repaintKey,
            child: _ShareCard(
              anime: widget.anime,
              status: widget.status,
              userRating: widget.userRating,
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isCapturing ? null : _downloadCard,
                  icon: _isCapturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_isCapturing ? 'Saving...' : 'Save Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  final Anime anime;
  final String? status;
  final double? userRating;

  static const _bg = Color(0xFF0A0414);

  const _ShareCard({
    required this.anime,
    this.status,
    this.userRating,
  });

  String _statusLabel(String? s) {
    switch (s) {
      case 'WATCHING':      return '👀 Watching';
      case 'COMPLETED':     return '✅ Completed';
      case 'PLAN_TO_WATCH': return '📌 Plan to Watch';
      case 'DROPPED':       return '❌ Dropped';
      default:              return '📋 In My List';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 160,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (anime.imageUrl != null)
              Positioned.fill(
                child: Image.network(
                  anime.imageUrl!,
                  fit: BoxFit.cover,
                  opacity: const AlwaysStoppedAnimation(0.25),
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [Colors.transparent, _bg],
                    stops: [0.3, 1.0],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                if (anime.imageUrl != null)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: Image.network(
                      anime.imageUrl!,
                      width: 110,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 110, height: 160, color: Colors.white12),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Logo row
                        Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: Image.asset(
                                'assets/images/hanj_wing_transparent.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Hanj',
                              style: TextStyle(
                                color: Color(0xFFF5F0E8),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        // Title + genres
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              anime.titleEnglish ?? anime.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            if (anime.genres.isNotEmpty)
                              Text(
                                anime.genres.take(2).join(' • '),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                        // Rating + status
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (userRating != null)
                              Row(
                                children: [
                                  ...List.generate(5, (i) {
                                    final starVal = (i + 1) * 2.0;
                                    return Icon(
                                      userRating! >= starVal
                                          ? Icons.star_rounded
                                          : userRating! >= starVal - 1
                                              ? Icons.star_half_rounded
                                              : Icons.star_outline_rounded,
                                      color: Colors.amber,
                                      size: 12,
                                    );
                                  }),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${userRating!.toStringAsFixed(1)}/10',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            if (status != null)
                              Text(
                                _statusLabel(status),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
