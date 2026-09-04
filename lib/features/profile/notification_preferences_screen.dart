import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notification Preferences Screen
// Drop this into your profile screen as a settings page
// ─────────────────────────────────────────────────────────────────────────────

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final _service = NotificationService.instance;

  Map<String, bool> _prefs = {};
  bool _loading = true;

  static const _items = [
    (
      key: 'new_season',
      icon: Icons.auto_awesome_rounded,
      title: 'New Season Alerts',
      subtitle: 'When a new anime season starts airing',
      color: AppTheme.primary,
    ),
    (
      key: 'episode_reminder',
      icon: Icons.play_circle_outline_rounded,
      title: 'Episode Reminders',
      subtitle: 'New episodes of anime in your Watching list',
      color: AppTheme.planToWatch,
    ),
    (
      key: 'weekly_recap',
      icon: Icons.bar_chart_rounded,
      title: 'Weekly Recap',
      subtitle: 'Your watch activity digest every Sunday',
      color: AppTheme.accent,
    ),
    (
      key: 'social',
      icon: Icons.people_outline_rounded,
      title: 'Friend Activity',
      subtitle: 'When friends add or complete anime',
      color: AppTheme.completed,
    ),
    (
      key: 'streak',
      icon: Icons.local_fire_department_rounded,
      title: 'Streak Alerts',
      subtitle: 'Reminders to keep your watching streak alive',
      color: Color(0xFFFF6B35),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _service.getPreferences();
    if (mounted) setState(() { _prefs = prefs; _loading = false; });
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _prefs[key] = value);
    try {
      await _service.setPreference(key, value);
    } catch (_) {
      // Save locally if Firestore fails
      setState(() => _prefs[key] = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Notifications',
            style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppTheme.primary, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notifications are sent by Hanj servers. '
                          'You can change these anytime.',
                          style: AppTheme.sans(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),

                // Toggle rows
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.cardBorder),
                  ),
                  child: Column(
                    children: _items.asMap().entries.map((entry) {
                      final i    = entry.key;
                      final item = entry.value;
                      final isLast = i == _items.length - 1;

                      return Column(
                        children: [
                          _PrefTile(
                            icon:     item.icon,
                            title:    item.title,
                            subtitle: item.subtitle,
                            color:    item.color,
                            value:    _prefs[item.key] ?? true,
                            onChanged: (v) => _toggle(item.key, v),
                          ),
                          if (!isLast)
                            Divider(
                              height: 1,
                              indent: 56,
                              color: AppTheme.border.withValues(alpha: 0.5),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preference tile
// ─────────────────────────────────────────────────────────────────────────────

class _PrefTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrefTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTheme.sans(
                        fontSize: 14,
                        weight: FontWeight.w500,
                        color: value
                            ? AppTheme.textPrimary
                            : AppTheme.textMuted)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppTheme.sans(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Toggle — custom, unified coral accent
          _ModernToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modern pill toggle — smooth, minimal, single accent color
// ─────────────────────────────────────────────────────────────────────────────

class _ModernToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ModernToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value
              ? AppTheme.primary
              : AppTheme.surfaceLight,
          border: Border.all(
            color: value
                ? AppTheme.primary
                : AppTheme.textMuted.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : AppTheme.textMuted,
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
