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

  bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi   ||
        r == ConnectivityResult.ethernet);
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

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
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
