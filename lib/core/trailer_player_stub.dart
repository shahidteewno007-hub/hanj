import 'package:flutter/material.dart';

// Web stub. The mobile YouTube player isn't used on web (web shows an inline
// iframe via trailer_launcher_web.dart). These just satisfy the conditional
// import so the shared trailer_launcher.dart compiles for web.
//
// Signatures must match trailer_player_mobile.dart exactly.
Widget buildPlayer(String videoId, {double? width}) => const SizedBox.shrink();

void disposePlayer() {}
