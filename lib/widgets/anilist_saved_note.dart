import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../services/anilist_service.dart';

/// A "saved, not live" marker for the three surfaces that keep AniList data on
/// disk and serve it when a fetch fails — `OfflineCacheService:148-150` and
/// `discovery_screen.dart:644`.
///
/// Serving yesterday's data through an outage is correct and stays exactly as
/// it is. The defect is silence: during the 2026-09-09 outage Home trending,
/// Discovery seasonal and title detail all looked live while AniList was
/// returning 403, which is worse than an empty screen because nothing suggests
/// the data is old.
///
/// Renders nothing while AniList is answering, so the healthy path costs one
/// `SizedBox.shrink()`.
class AnilistSavedNote extends StatelessWidget {
  const AnilistSavedNote({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 10),
  });

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (!AnilistService.isUnavailable) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Text(
        'SAVED DATA · ANILIST UNAVAILABLE',
        style: AppTheme.mono(
          fontSize: 9,
          color: AppTheme.textMuted,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
