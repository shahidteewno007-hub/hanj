import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/tier_list/tier_list_home_screen.dart';

/// Entry point for building Tier lists in isolation, as lib/cadre_dev.dart is
/// for Cadre. Unreferenced by design: nothing in the app imports it.
///
/// Run with:  flutter run -t lib/tier_list_dev.dart
///
/// Tier lists need no Firebase: lists are saved on the device and the
/// characters come from AniList, through the same shared throttle as the
/// app. So this opens straight onto the start screen, under Hanj's dark
/// theme, exactly as the '/tierlist' route shows it.
void main() {
  runApp(const TierListDevApp());
}

class TierListDevApp extends StatelessWidget {
  const TierListDevApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanj tier lists',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const TierListHomeScreen(),
    );
  }
}
