import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Connectivity Service
// ─────────────────────────────────────────────────────────────────────────────

class ConnectivityService {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  final _connectivity = Connectivity();
  final _controller   = StreamController<bool>.broadcast();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Stream<bool> get onConnectivityChanged => _controller.stream;

  Future<void> init() async {
    try {
      // Initial check with timeout so it never hangs
      final result = await _connectivity.checkConnectivity()
          .timeout(const Duration(seconds: 3), onTimeout: () => [ConnectivityResult.none]);
      _isOnline = _isConnected(result);

      // Listen for changes
      _connectivity.onConnectivityChanged.listen((result) {
        final online = _isConnected(result);
        if (online != _isOnline) {
          _isOnline = online;
          _controller.add(online);
        }
      });
    } catch (_) {
      _isOnline = true; // assume online if check fails
    }
  }

  // connectivity_plus names a transport only for a network that has
  // internet (NET_CAPABILITY_INTERNET) and says `none` otherwise, so any
  // other answer is online. Counting only mobile, Wi-Fi and Ethernet read a
  // VPN-only connection (the test phone's USB internet, gnirehtet) as
  // offline, and Bluetooth tethering too.
  bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  void dispose() => _controller.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline Banner
// Wrap around any screen's body to automatically show/hide the banner
//
// Usage:
//   body: OfflineBanner(child: YourWidget()),
// ─────────────────────────────────────────────────────────────────────────────

class OfflineBanner extends StatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});

  /// The page's top inset is the device's (top-inset, 2026-11-16). The pill
  /// used to sit in a Column above the page and slide out of sight, which
  /// kept its height: every tab started ~36 dp down whatever the status bar
  /// was, a sumi strip under a 29 dp one (LG V60) and the page under a 40 dp
  /// one (CPH2573), and the pill itself showed mostly under the status bar.
  /// Now the pill takes no room while it's hidden and the page gets the
  /// status bar's height as its top padding. Shown, the pill runs under the
  /// status bar with its words below it, pushes the page down by its own
  /// height and takes the page's top padding over, so nothing is covered
  /// and nothing is inset twice. Home and Profile read this to pad by the
  /// status bar themselves. false is the reserved height, as before.
  static const bool deviceInset = true;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  // How much of the pill shows (deviceInset): 0 hidden, 1 all of it.
  late Animation<double> _shown;
  late StreamSubscription<bool> _sub;

  bool _isOnline = true;

  @override
  void initState() {
    super.initState();

    _isOnline = ConnectivityService.instance.isOnline;

    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _shown = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    if (!_isOnline) _ctrl.forward();

    _sub = ConnectivityService.instance.onConnectivityChanged.listen((online) {
      setState(() => _isOnline = online);
      if (!online) {
        _ctrl.forward();
      } else {
        // Show "Back online" briefly then slide away completely
        _ctrl.forward();
        Future.delayed(const Duration(milliseconds: 2000), () {
          if (mounted) _ctrl.reverse();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (OfflineBanner.deviceInset) return _buildOverInset(context);
    return Column(
      children: [
        SlideTransition(
          position: _slide,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: _isOnline
                ? AppTheme.completed.withValues(alpha: 0.9)
                : AppTheme.dropped.withValues(alpha: 0.9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isOnline
                      ? Icons.wifi_rounded
                      : Icons.wifi_off_rounded,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  _isOnline ? 'Back online' : 'You\'re offline',
                  style: AppTheme.sans(
                      fontSize: 12,
                      color: Colors.white,
                      weight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }

  /// The pill and the page with the device's inset (deviceInset). The pill
  /// is revealed from its foot, so it comes down from the top as the slide
  /// did. While a fraction f of it shows, the page's top padding is (1 - f)
  /// of the status bar's, so the page's content moves down by exactly the
  /// pill's own height, smoothly, without measuring it. Hidden, the page's
  /// MediaQuery equals the window's and nothing under it rebuilds.
  Widget _buildOverInset(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top;
    return AnimatedBuilder(
      animation: _shown,
      child: widget.child,
      builder: (context, page) {
        final shown = _shown.value.clamp(0.0, 1.0);
        final taken = top * shown;
        return Column(
          children: [
            ClipRect(
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: shown,
                // A hidden pill isn't read out, as the slid-away one was.
                child: ExcludeSemantics(
                  excluding: shown == 0,
                  child: _insetPill(top),
                ),
              ),
            ),
            Expanded(
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(top: top - taken),
                  viewPadding: media.viewPadding.copyWith(
                      top: (media.viewPadding.top - taken)
                          .clamp(0.0, double.infinity)),
                ),
                child: page!,
              ),
            ),
          ],
        );
      },
    );
  }

  /// build()'s pill, with [top] more room above its words: its colour runs
  /// under the status bar and its words sit below it.
  Widget _insetPill(double top) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 8 + top, 16, 8),
      color: _isOnline
          ? AppTheme.completed.withValues(alpha: 0.9)
          : AppTheme.dropped.withValues(alpha: 0.9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isOnline
                ? Icons.wifi_rounded
                : Icons.wifi_off_rounded,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 8),
          Text(
            _isOnline ? 'Back online' : 'You\'re offline',
            style: AppTheme.sans(
                fontSize: 12,
                color: Colors.white,
                weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Offline-aware builder
// Use this instead of FutureBuilder when data may come from cache
//
// Usage:
//   OfflineAwareBuilder<List<Anime>>(
//     future: cache.getTrending(),
//     builder: (context, anime, isFromCache) => ...
//   )
// ─────────────────────────────────────────────────────────────────────────────

class OfflineAwareBuilder<T> extends StatefulWidget {
  final Future<T> future;
  final Widget Function(BuildContext, T, bool isFromCache) builder;
  final Widget? loading;
  final Widget? error;

  const OfflineAwareBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.loading,
    this.error,
  });

  @override
  State<OfflineAwareBuilder<T>> createState() =>
      _OfflineAwareBuilderState<T>();
}

class _OfflineAwareBuilderState<T> extends State<OfflineAwareBuilder<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.future;
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ConnectivityService.instance.isOnline;

    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return widget.loading ??
              const Center(
                child: CircularProgressIndicator(
                    color: AppTheme.primary, strokeWidth: 2),
              );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return widget.error ??
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        size: 48, color: AppTheme.textMuted),
                    const SizedBox(height: 12),
                    Text('No data available offline',
                        style: AppTheme.sans(
                            color: AppTheme.textSecondary, fontSize: 14)),
                  ],
                ),
              );
        }

        return widget.builder(context, snapshot.data as T, !isOnline);
      },
    );
  }
}
