import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

const _coral = Color(0xFFE8624A);

YoutubePlayerController? _ctrl;
String? _currentId;

// Build the trailer player.
//
// IMPORTANT: this is now idempotent. The OLD version created a brand-new
// controller on every call, and because it runs inside build(), every rebuild
// (including the rebuild that fires when the screen rotates to landscape) tore
// down the controller and made a fresh, non-fullscreen one — which is exactly
// why fullscreen "opened for a second then shrank". Now the controller is
// created once per videoId and reused across rebuilds, so rotation/resizes no
// longer interrupt playback.
//
// We also return a bare YoutubePlayer (no YoutubePlayerBuilder) with the
// in-player fullscreen (++) button removed from bottomActions. TrailerPlayerScreen
// is already landscape + fullscreen, so the package's own fullscreen handling —
// the thing that was fighting orientation — is never invoked.
//
// [width] is the fitted player width computed by the screen (largest 16:9 that
// fits the display) so the video letterboxes/pillarboxes cleanly instead of
// overflowing and cropping the subtitles.
Widget buildPlayer(String videoId, {double? width}) {
  if (_ctrl == null || _currentId != videoId) {
    _ctrl?.dispose();
    _currentId = videoId;
    _ctrl = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        enableCaption: false,
      ),
    );
  }

  return YoutubePlayer(
    controller: _ctrl!,
    width: width,
    aspectRatio: 16 / 9,
    showVideoProgressIndicator: true,
    progressIndicatorColor: _coral,
    progressColors: const ProgressBarColors(
      playedColor: _coral,
      handleColor: _coral,
    ),
    // Custom control bar WITHOUT FullScreenButton — that toggle is what
    // bounced the player back to a small size.
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
  );
}

void disposePlayer() {
  _ctrl?.dispose();
  _ctrl = null;
  _currentId = null;
}
