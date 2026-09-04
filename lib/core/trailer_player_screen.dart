import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// Fullscreen trailer player.
///
/// Takes full control of orientation + system UI itself instead of using the
/// YouTube package's built-in fullscreen toggle. That toggle is what was
/// bouncing back to a small player: a global portrait lock (likely in
/// main.dart) snaps the app back to portrait the instant the package rotates
/// to landscape, so fullscreen "opens for a second then shrinks".
///
/// Here the SCREEN is the fullscreen: forced landscape + immersive on open,
/// restored to portrait + visible bars on exit (which also fixes the stuck
/// "swipe again to go back" bars).
class TrailerPlayerScreen extends StatefulWidget {
  final String videoId;
  const TrailerPlayerScreen({super.key, required this.videoId});

  @override
  State<TrailerPlayerScreen> createState() => _TrailerPlayerScreenState();
}

class _TrailerPlayerScreenState extends State<TrailerPlayerScreen> {
  late final YoutubePlayerController _controller;

  static const _coral = Color(0xFFE8624A);

  @override
  void initState() {
    super.initState();

    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: false,
      ),
    );

    // Force landscape + hide both bars for as long as this screen is alive.
    // This overrides any global portrait lock from main.dart.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _controller.dispose();
    // Restore portrait + bring the system bars back. manual + both overlays
    // hard-breaks out of immersive-sticky.
    // If Hanj supports rotation elsewhere, change [portraitUp] to
    // DeviceOrientation.values.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Player fills the screen (as large as 16:9 fits — same framing as
          // YouTube's own fullscreen, no distortion, no subtitle cropping).
          Positioned.fill(
            child: Center(
              child: YoutubePlayer(
                controller: _controller,
                aspectRatio: 16 / 9,
                showVideoProgressIndicator: true,
                progressIndicatorColor: _coral,
                progressColors: const ProgressBarColors(
                  playedColor: _coral,
                  handleColor: _coral,
                ),
                // Drop the in-player fullscreen toggle — it's what fought the
                // rotation and caused the bounce. Keep the rest of the bar.
                bottomActions: [
                  const SizedBox(width: 14),
                  CurrentPosition(),
                  const SizedBox(width: 8),
                  ProgressBar(
                    isExpanded: true,
                    colors: const ProgressBarColors(
                      playedColor: _coral,
                      handleColor: _coral,
                    ),
                  ),
                  const SizedBox(width: 8),
                  RemainingDuration(),
                  const SizedBox(width: 14),
                ],
              ),
            ),
          ),
          // Close button.
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
