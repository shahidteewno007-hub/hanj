import 'package:flutter/material.dart';

/// Wraps any widget with hover effects: scale up + glow
class HoverAnimeCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color glowColor;

  const HoverAnimeCard({
    super.key,
    required this.child,
    required this.onTap,
    this.glowColor = const Color(0xFF6C5CE7),
  });

  @override
  State<HoverAnimeCard> createState() => _HoverAnimeCardState();
}

class _HoverAnimeCardState extends State<HoverAnimeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0),
          decoration: BoxDecoration(
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: widget.glowColor.withOpacity(0.6),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
