import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'theme/app_theme.dart';
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

  // Hanko (question 112): washi on sumi, with no glow and no coral, which
  // marks only your own verdicts. It was a red disc with a red glow and a
  // red "Watch Trailer" pill. Detail's Overview and Pulse's trailer sheet
  // (web) both use this widget; Pulse's own trailer card already draws its
  // play mark light on dark, so the sheet now matches the card it opens from.
  @override
  Widget build(BuildContext context) {
    if (_videoId == null) return const SizedBox.shrink();
    final playing = _showPlayer && kIsWeb;

    return LayoutBuilder(builder: (context, constraints) {
      // The video's own 16:9, so hqdefault's letterbox bars fall outside the
      // frame on a phone (320 wide: 180 tall), up to the old 200 tall on
      // wider screens. The web player takes the same frame, so nothing jumps.
      final width = constraints.maxWidth;
      final height = width * 9 / 16 < 200 ? width * 9 / 16 : 200.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Inline iframe (web only) ──────────────────────────
          if (playing)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: platform.buildIframeView(_videoId!),
              ),
            )

          // ── Thumbnail (mobile + web before tap) ──────────────
          // Left out of the semantics tree: the row under it does the same
          // with words, as one button. Unlabelled, it was a nameless tap.
          else
            ExcludeSemantics(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _handleTap(context),
                  child: Container(
                    width: double.infinity,
                    height: height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                      // Sumi 3, as Hanko's covers: what shows while the
                      // picture loads, when it fails, or offline.
                      color: AppTheme.hankoSumi3,
                      image: DecorationImage(
                        image: NetworkImage(
                            'https://img.youtube.com/vi/$_videoId/hqdefault.jpg'),
                        fit: BoxFit.cover,
                        // Offline, or a 404 for a removed video: leave the
                        // sumi frame. Unhandled, the failure went to
                        // Crashlytics as fatal.
                        onError: (_, _) {},
                      ),
                    ),
                    // The play mark: a washi triangle on a sumi tile with an
                    // edge keyline, readable on any picture. No shadow.
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.hankoSumi.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                          border: Border.all(color: AppTheme.hankoEdge),
                        ),
                        child: const Icon(Icons.play_arrow_sharp,
                            color: AppTheme.hankoWashi, size: 32),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 4),

          // ── The row ───────────────────────────────────────────
          // A plain 48 dp row in washi, as Detail's "Join the discussion":
          // Hanko keeps pills for controls that change something. On mobile
          // it opens the player, as the picture does; on the web it shows or
          // closes the inline player. Its own semantics node with the
          // InkWell's tap and focus (question 104's container pattern).
          Semantics(
            container: true,
            button: true,
            child: InkWell(
              onTap: () {
                if (kIsWeb) {
                  setState(() => _showPlayer = !_showPlayer);
                } else {
                  _handleTap(context);
                }
              },
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
                child: Row(
                  children: [
                    Icon(playing ? Icons.close_sharp : Icons.play_arrow_sharp,
                        size: 20, color: AppTheme.hankoWashi),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        playing ? 'Close the trailer' : 'Watch the trailer',
                        style: AppTheme.hankoSans(fontSize: 15, weight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}
