import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';

/// Analytics stays off until a Yes (code batch 1, audit Q183, LR-016).
///
/// Collection starts disabled: on Android by the manifest's
/// `firebase_analytics_collection_enabled` set to false, and on the web by
/// never touching Analytics until a Yes ([AnalyticsGate] forwards screen
/// views only then). A plain Yes or No sheet asks once, after onboarding
/// ([maybeAsk]); the answer is kept on this device. "Share usage data" in
/// Profile's More sheet turns it off again ([setConsent]).
///
/// Crashlytics is not part of this; it stays on, as the audit recommends.
class AnalyticsConsent {
  AnalyticsConsent._();
  static final instance = AnalyticsConsent._();

  /// False gives back main as it was: collection on from launch, no sheet,
  /// no switch in More.
  static const bool askFirst = true;

  static const _key = 'hanj.analyticsConsent.v1';

  /// Null: not asked yet. True: Yes. False: No.
  final ValueNotifier<bool?> consent = ValueNotifier<bool?>(null);

  bool _loaded = false;

  /// Reads the stored answer and sets collection to match. Called once from
  /// main() before runApp; never throws.
  Future<void> load() async {
    if (!askFirst) {
      consent.value = true;
      _loaded = true;
      _apply(true);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      consent.value = prefs.getBool(_key);
    } catch (_) {
      consent.value = null;
    }
    _loaded = true;
    // Only a stored Yes touches Analytics; otherwise it is never started.
    if (consent.value == true) _apply(true);
  }

  Future<void> setConsent(bool yes) async {
    consent.value = yes;
    _apply(yes);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, yes);
    } catch (_) {}
  }

  /// Whether Analytics was started this run. A No before that leaves it
  /// untouched: on the web even setting collection off creates Analytics,
  /// which fetches its config (seen in the batch 1 web check), and on
  /// Android the manifest already has it off.
  bool _started = false;

  void _apply(bool on) {
    if (!on && !_started) return;
    _started = true;
    try {
      FirebaseAnalytics.instance
          .setAnalyticsCollectionEnabled(on)
          .catchError((Object _) {});
    } catch (_) {}
  }

  /// Shows the Yes or No sheet once, if this device hasn't answered.
  Future<void> maybeAsk(BuildContext context) async {
    if (!askFirst || !_loaded || consent.value != null) return;
    final yes = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppTheme.hankoSumi2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.hankoRadius)),
      ),
      builder: (sheetCtx) => const _ConsentSheet(),
    );
    if (yes != null) await setConsent(yes);
  }
}

class _ConsentSheet extends StatelessWidget {
  const _ConsentSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, 24, AppTheme.hankoGutter, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('Share how you use Hanj?',
                  style: AppTheme.hankoSerif(
                      fontSize: AppTheme.hankoSectionSize, height: 1.3)),
            ),
            const SizedBox(height: 10),
            Text(
              'If you say yes, Hanj counts which screens you open, with '
              'basic facts about your device, through Google Analytics for '
              'Firebase. Your list and ratings aren’t part of it, and no '
              'advertising ID is used. You can turn it off any time in '
              'Profile, under More.',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  color: AppTheme.hankoStone,
                  height: 1.5),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.hankoWashi,
                      side: const BorderSide(color: AppTheme.hankoEdge),
                      minimumSize: const Size.fromHeight(AppTheme.hankoTouch),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(
                              Radius.circular(AppTheme.hankoRadius))),
                    ),
                    child: Text('No',
                        style: AppTheme.hankoSans(
                            fontSize: 15, weight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.hankoWashi,
                      foregroundColor: AppTheme.hankoSumi,
                      minimumSize: const Size.fromHeight(AppTheme.hankoTouch),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(
                              Radius.circular(AppTheme.hankoRadius))),
                    ),
                    child: Text('Yes',
                        style: AppTheme.hankoSans(
                            fontSize: 15,
                            weight: FontWeight.w600,
                            color: AppTheme.hankoSumi)),
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

/// The app's analytics observer, forwarding screen views to Firebase only
/// after a Yes. Until then Firebase Analytics is never created, so the web
/// loads nothing of it. With [AnalyticsConsent.askFirst] off it forwards
/// everything, as main's FirebaseAnalyticsObserver did.
class AnalyticsGate extends NavigatorObserver {
  FirebaseAnalyticsObserver? _inner;

  FirebaseAnalyticsObserver? get _observer {
    if (AnalyticsConsent.instance.consent.value != true) return null;
    return _inner ??=
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _observer?.didPush(route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _observer?.didReplace(newRoute: newRoute, oldRoute: oldRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _observer?.didPop(route, previousRoute);
}
