import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'cadre/screens/cadre_lobby_screen.dart';
import 'cadre/widgets/cadre_fighter_card.dart';

/// Temporary entry point for building Cadre in isolation.
///
/// Run with:  flutter run -t lib/cadre_dev.dart
///
/// THEME PROBE
/// Cadre has only ever run under its own hardcoded dark theme. Once it lives
/// inside Hanj it inherits Hanj's theme instead, which may be light. This flag
/// runs the lobby under the exact ThemeData Hanj will hand it, so any screen
/// that depends on the ambient theme shows itself now rather than after wiring.
///
///   0 = Cadre's own dark theme  (how it has been running so far)
///   1 = Hanj light theme        (worst case once wired — test this first)
///   2 = Hanj dark theme         (most likely case once wired)
const int kProbeTheme = 1;

void main() {
  runApp(const CadreDevApp());
}

class CadreDevApp extends StatelessWidget {
  const CadreDevApp({super.key});

  ThemeData get _theme {
    switch (kProbeTheme) {
      case 1:
        return AppTheme.lightTheme;
      case 2:
        return AppTheme.darkTheme;
      default:
        return ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: CadreColors.bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: CadreColors.coral,
            brightness: Brightness.dark,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cadre',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: const CadreLobbyScreen(),
    );
  }
}
