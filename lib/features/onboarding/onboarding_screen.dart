import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  int _currentPage = 0;

  // Import page state
  String? _selectedImport; // 'anilist' | 'mal' | null (skip)

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const _coral   = Color(0xFFE8624A);
  static const _magenta = Color(0xFFCA2868);
  static const _bg      = Color(0xFF0D0B09);
  static const _cream   = Color(0xFFF5F0E8);

  static const _contentPages = [
    _PageData(
      icon: Icons.play_circle_outline_rounded,
      iconColor: Color(0xFFE8624A),
      tag: 'WELCOME',
      title: 'Welcome to\nHanj',
      subtitle: 'Track, discover and share\nyour anime journey.\nThe pull is real.',
      accentColor: Color(0xFFE8624A),
    ),
    _PageData(
      icon: Icons.format_list_bulleted_rounded,
      iconColor: Color(0xFF4A9B6F),
      tag: 'YOUR LIST',
      title: 'Track\nEverything',
      subtitle: 'Add anime to Watching,\nCompleted, Plan to Watch\nor Dropped. Rate and note.',
      accentColor: Color(0xFF4A9B6F),
    ),
    _PageData(
      icon: Icons.explore_rounded,
      iconColor: Color(0xFF4A7FB5),
      tag: 'DISCOVER',
      title: 'Find New\nAnime',
      subtitle: 'Browse trending, top rated\nand seasonal anime.\nFilter by genre, year and format.',
      accentColor: Color(0xFF4A7FB5),
    ),
    _PageData(
      icon: Icons.people_outline_rounded,
      iconColor: Color(0xFFD4A96A),
      tag: 'COMMUNITY',
      title: 'Share Your\nJourney',
      subtitle: 'Follow friends, see their\nactivity and share your\nanime card with the world.',
      accentColor: Color(0xFFD4A96A),
    ),
  ];

  // Total pages = content pages + import page
  int get _totalPages => _contentPages.length + 1;
  bool get _isImportPage => _currentPage == _contentPages.length;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      // Just drive the PageView; onPageChanged handles the content fade.
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    // Save import intent to Firestore if user is signed in
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'importIntent': _selectedImport,      // 'anilist' | 'mal' | null
          'importPending': _selectedImport != null,
          'onboardingComplete': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Import intent save error: $e');
    }

    // No manual navigation: the _OnboardingGate stream in AuthWrapper sees
    // onboardingComplete: true and swaps to MainScreen automatically.
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _isImportPage
        ? _coral
        : _contentPages[_currentPage].accentColor;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Animated radial glow
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 1.2,
                colors: [
                  accentColor.withValues(alpha: 0.15),
                  _bg.withValues(alpha: 0.8),
                  _bg,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Dot grid
          const Positioned.fill(child: _DotGrid()),

          // Pages
          PageView.builder(
            controller: _pageController,
            onPageChanged: (i) {
              setState(() => _currentPage = i);
              _fadeCtrl.forward(from: 0.4);
            },
            itemCount: _totalPages,
            itemBuilder: (_, i) {
              if (i == _contentPages.length) {
                return _ImportPageContent(
                  fadeAnim: _fadeAnim,
                  selectedImport: _selectedImport,
                  onSelect: (val) => setState(() => _selectedImport = val),
                );
              }
              return _PageContent(
                page: _contentPages[i],
                fadeAnim: _fadeAnim,
              );
            },
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    _bg.withValues(alpha: 0.9),
                    _bg,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Skip — hidden on last page
                  _currentPage < _totalPages - 1
                      ? TextButton(
                          onPressed: _finish,
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 15,
                            ),
                          ),
                        )
                      : const SizedBox(width: 60),

                  // Dots
                  Row(
                    children: List.generate(
                      _totalPages,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _currentPage == i ? 20 : 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? _coral
                              : Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),

                  // Next / Get Started
                  GestureDetector(
                    onTap: _nextPage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 13),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [_coral, _magenta]),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: _coral.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isImportPage ? 'Get Started' : 'Next',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded,
                              color: Colors.white, size: 15),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Import page
// ─────────────────────────────────────────────────────────────────────────────

class _ImportPageContent extends StatelessWidget {
  final Animation<double> fadeAnim;
  final String? selectedImport;
  final ValueChanged<String?> onSelect;

  const _ImportPageContent({
    required this.fadeAnim,
    required this.selectedImport,
    required this.onSelect,
  });

  static const _coral = Color(0xFFE8624A);
  static const _cream = Color(0xFFF5F0E8);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnim,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 130),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wing mark logo
              Image.asset(
                'assets/images/hanj_wing_transparent.png',
                width: 72,
                height: 72,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 28),

              // Tag
              Text(
                'IMPORT',
                style: GoogleFonts.spaceGrotesk(
                  color: _coral,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.0,
                ),
              ),

              const SizedBox(height: 14),

              // Title
              Text(
                'Bring Your\nList Along',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),

              const SizedBox(height: 18),

              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: _coral,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Already tracking on AniList or MAL?\nWe\'ll import your list after you sign in.',
                style: AppTheme.sans(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 28),

              // Import options
              _ImportOption(
                label: 'Import from AniList',
                sublabel: 'anilist.co',
                color: const Color(0xFF02A9FF),
                selected: selectedImport == 'anilist',
                onTap: () => onSelect(
                  selectedImport == 'anilist' ? null : 'anilist',
                ),
              ),

              const SizedBox(height: 12),

              _ImportOption(
                label: 'Import from MyAnimeList',
                sublabel: 'myanimelist.net',
                color: const Color(0xFF2E51A2),
                selected: selectedImport == 'mal',
                onTap: () => onSelect(
                  selectedImport == 'mal' ? null : 'mal',
                ),
              ),

              const SizedBox(height: 16),

              // Skip hint
              Center(
                child: Text(
                  selectedImport == null
                      ? 'Or tap Get Started to skip — you can import later in Settings.'
                      : 'We\'ll remind you to complete the import once you\'re in.',
                  textAlign: TextAlign.center,
                  style: AppTheme.sans(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportOption extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ImportOption({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Color dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),

            const SizedBox(width: 14),

            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTheme.sans(
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                      weight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: AppTheme.sans(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            // Checkmark
            AnimatedOpacity(
              opacity: selected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.check_circle_rounded, color: color, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// Mini wing mark for import page icon
class _WingMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final featherPaint = Paint()
      ..color = const Color(0xFFF5F0E8).withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final featherPath = Path();
    featherPath.moveTo(w * 0.30, h * 0.88);
    featherPath.cubicTo(w * 0.22, h * 0.68, w * 0.28, h * 0.42, w * 0.48, h * 0.24);
    featherPath.cubicTo(w * 0.60, h * 0.12, w * 0.78, h * 0.08, w * 0.88, h * 0.12);
    featherPath.cubicTo(w * 0.68, h * 0.24, w * 0.52, h * 0.40, w * 0.44, h * 0.60);
    featherPath.cubicTo(w * 0.37, h * 0.76, w * 0.36, h * 0.84, w * 0.38, h * 0.90);
    featherPath.close();
    canvas.drawPath(featherPath, featherPaint);

    final quillPaint = Paint()
      ..color = const Color(0xFFE8624A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;

    final quill = Path();
    quill.moveTo(w * 0.84, h * 0.14);
    quill.cubicTo(w * 0.64, h * 0.36, w * 0.46, h * 0.62, w * 0.32, h * 0.86);
    canvas.drawPath(quill, quillPaint);
  }

  @override
  bool shouldRepaint(_WingMarkPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _PageData {
  final IconData icon;
  final Color iconColor;
  final String tag;
  final String title;
  final String subtitle;
  final Color accentColor;

  const _PageData({
    required this.icon,
    required this.iconColor,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Page content
// ─────────────────────────────────────────────────────────────────────────────

class _PageContent extends StatelessWidget {
  final _PageData page;
  final Animation<double> fadeAnim;

  const _PageContent({required this.page, required this.fadeAnim});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnim,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: page.accentColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: page.accentColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: page.accentColor.withValues(alpha: 0.2),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(page.icon, color: page.accentColor, size: 36),
              ),

              const SizedBox(height: 36),

              Text(
                page.tag,
                style: GoogleFonts.spaceGrotesk(
                  color: page.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.0,
                ),
              ),

              const SizedBox(height: 14),

              Text(
                page.title,
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 50,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),

              const SizedBox(height: 20),

              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: page.accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                page.subtitle,
                style: AppTheme.sans(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 16,
                  height: 1.75,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dot grid
// ─────────────────────────────────────────────────────────────────────────────

class _DotGrid extends StatelessWidget {
  const _DotGrid();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DotPainter(), size: Size.infinite);
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1520)
      ..style = PaintingStyle.fill;
    const spacing = 14.0;
    const radius  = 0.9;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotPainter _) => false;
}
