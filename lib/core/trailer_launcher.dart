import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'trailer_launcher_web.dart' if (dart.library.io) 'trailer_launcher_stub.dart' as platform;
import 'trailer_player_mobile.dart' if (dart.library.html) 'trailer_player_stub.dart' as mobile;

String? extractYouTubeId(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.queryParameters.containsKey('v')) return uri.queryParameters['v'];
  if (uri.host == 'youtu.be') return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  return null;
}

// ── Full-screen player route (mobile) ────────────────────────
// The SCREEN itself is the fullscreen: on open we force landscape and hide
// both system bars, on close we restore portrait + bars. The player widget
// (built in trailer_player_mobile.dart) creates its controller ONCE and has
// no in-player fullscreen (++) button — so nothing toggles orientation behind
// our back and nothing tears the controller down on rebuild. That removes the
// old "opens fullscreen for a second then shrinks" bounce.
class TrailerPlayerScreen extends StatefulWidget {
  final String videoId;
  const TrailerPlayerScreen({super.key, required this.videoId});

  @override
  State<TrailerPlayerScreen> createState() => _TrailerPlayerScreenState();
}

class _TrailerPlayerScreenState extends State<TrailerPlayerScreen> {
  @override
  void initState() {
    super.initState();
    // Force landscape + hide both bars. Hanj has no global orientation lock
    // (checked main.dart + AndroidManifest), so this takes effect immediately
    // and nothing snaps it back.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore portrait + bring the system bars back. manual + BOTH overlays
    // hard-breaks out of immersive-sticky (the fix for the stuck
    // "swipe again to go back" bars).
    //
    // NOTE: this re-locks the app to portrait on the way out. Hanj currently
    // rotates freely (no lock anywhere), and for an anime tracker portrait-only
    // is almost certainly what you want. If you DO intend to support landscape
    // elsewhere, change [portraitUp] below to DeviceOrientation.values.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    mobile.disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // Largest 16:9 box that fits the screen — letterbox/pillarbox, never a
    // crop, so subtitles stay on screen. Sizing the player natively (rather
    // than scaling it with a transform) keeps the video's platform view
    // aligned.
    final playerWidth =
        size.width < size.height * 16 / 9 ? size.width : size.height * 16 / 9;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: mobile.buildPlayer(widget.videoId, width: playerWidth),
            ),
          ),
          // Close button (replaces the old AppBar so it doesn't eat space).
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── TrailerButton ─────────────────────────────────────────────
// Web:    tap thumbnail → expand inline iframe (unchanged).
// Mobile: tap thumbnail → push TrailerPlayerScreen (new route).
//         This means the player is never embedded inside a
//         scroll view, so fullscreen just works.
class TrailerButton extends StatefulWidget {
  final String trailerUrl;
  const TrailerButton({super.key, required this.trailerUrl});

  @override
  State<TrailerButton> createState() => _TrailerButtonState();
}

class _TrailerButtonState extends State<TrailerButton> {
  bool _showPlayer = false; // web only — mobile goes to a new route
  String? _videoId;

  @override
  void initState() {
    super.initState();
    _videoId = extractYouTubeId(widget.trailerUrl);
    if (kIsWeb && _videoId != null) platform.registerIframe(_videoId!);
  }

  // No mobile.disposePlayer() here — the player lives in
  // TrailerPlayerScreen which handles its own disposal.

  void _handleTap(BuildContext context) {
    if (_videoId == null) return;
    if (kIsWeb) {
      setState(() => _showPlayer = true);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrailerPlayerScreen(videoId: _videoId!),
          fullscreenDialog: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_videoId == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Inline iframe (web only) ──────────────────────────
        if (_showPlayer && kIsWeb)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: double.infinity,
              height: 220,
              child: platform.buildIframeView(_videoId!),
            ),
          )

        // ── Thumbnail (mobile + web before tap) ──────────────
        else
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _handleTap(context),
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.black,
                  image: DecorationImage(
                    image: NetworkImage(
                        'https://img.youtube.com/vi/$_videoId/hqdefault.jpg'),
                    fit: BoxFit.cover,
                    opacity: 0.7,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 36),
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 8),

        // ── Toggle button ─────────────────────────────────────
        // On mobile this toggles nothing (always shows thumbnail),
        // but we still render it as "Watch Trailer" for consistency.
        GestureDetector(
          onTap: () {
            if (kIsWeb) {
              setState(() => _showPlayer = !_showPlayer);
            } else {
              _handleTap(context);
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade700.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Colors.red.shade700.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showPlayer && kIsWeb
                      ? Icons.stop_rounded
                      : Icons.play_circle_filled_rounded,
                  color: Colors.red.shade400,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  _showPlayer && kIsWeb ? 'Close Trailer' : 'Watch Trailer',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
