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
///
/// Listens to `AnilistService.failStatus`, so it redraws itself the moment the
/// status changes. It used to read the flag only when its screen built, which
/// missed changes both ways: an offline cold start built Home from cache before
/// the first request failed, so no marker until a tab switch, and after
/// reconnecting the marker lingered until one more rebuild. Only this widget
/// rebuilds; the screen around it doesn't.
class AnilistSavedNote extends StatelessWidget {
  const AnilistSavedNote({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 10),
  });

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: AnilistService.failStatus,
      builder: (context, code, _) {
        if (code == null) return const SizedBox.shrink();
        // Two causes the app can actually tell apart: no response at all
        // (status 0 — no network, DNS, timeout) versus a response that
        // wasn't a 200. Neither names a reason the app can't verify.
        final noResponse = code == 0;
        return Padding(
          padding: padding,
          child: Text(
            noResponse
                ? 'SAVED DATA · CAN\'T CONNECT'
                : 'SAVED DATA · COULDN\'T REFRESH',
            style: AppTheme.mono(
              fontSize: 9,
              color: AppTheme.textMuted,
              letterSpacing: 1.2,
            ),
          ),
        );
      },
    );
  }
}
