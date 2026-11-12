import 'package:flutter/material.dart';
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
  static const _bg      = Color(0xFF121110);
  static const _cream   = Color(0xFFF5F0E8);

  /// Onboarding in flat Hanko (the Vibes report's next stage): washi on
  /// sumi, Shippori headings, the pages' icons on sumi 3 tiles, the import
  /// choices as sumi 2 panels with a washi keyline when chosen (CLAUDE.md:
  /// never coral, which is only ever your verdicts), washi and edge page
  /// marks, and Next as the washi main action. Every page, choice and write
  /// is the same. False gives back the coloured glow, the dot grid, the
  /// coloured accents and the coral gradient button as they were.
  static const bool _printRoom = true;

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
      if (_printRoom && MediaQuery.disableAnimationsOf(context)) {
        // Motion off: the next page arrives without the slide.
        _pageController.jumpToPage(_currentPage + 1);
        return;
      }
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
    if (_printRoom) return _printed(context);
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

  /// The screen in flat Hanko: plain sumi, the pages above and the controls
  /// below them (no overlay, so nothing scrolls under Next). Skip, the page
  /// marks and Next sit in one row; Skip still leaves on the last page.
  Widget _printed(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final Animation<double> fade = still ? kAlwaysCompleteAnimation : _fadeAnim;
    return Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (i) {
                setState(() => _currentPage = i);
                _fadeCtrl.forward(from: 0.4);
              },
              itemCount: _totalPages,
              itemBuilder: (_, i) {
                if (i == _contentPages.length) {
                  return _PrintedImportPage(
                    fadeAnim: fade,
                    selectedImport: _selectedImport,
                    onSelect: (val) => setState(() => _selectedImport = val),
                  );
                }
                return _PrintedPage(page: _contentPages[i], fadeAnim: fade);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _kPrintedMeasure + 40),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.hankoGutter, 8, AppTheme.hankoGutter, 20),
                  child: Row(
                    children: [
                      // Skip — hidden on last page
                      if (_currentPage < _totalPages - 1)
                        _PrintedTextAction(label: 'Skip', onTap: _finish)
                      else
                        const SizedBox(width: AppTheme.hankoTouch),
                      Expanded(
                        child: Center(
                          child: _PrintedPageMarks(
                            count: _totalPages,
                            current: _currentPage,
                          ),
                        ),
                      ),
                      _PrintedMainAction(
                        label: _isImportPage ? 'Get Started' : 'Next',
                        onTap: _nextPage,
                      ),
                    ],
                  ),
                ),
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
              // The mark, with its flash
              Image.asset(
                'assets/images/hanj_cut.png',
                width: 72,
                height: 72,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 28),

              // Tag
              Text(
                'IMPORT',
                style: AppTheme.jostTabular(
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
                style: AppTheme.shipporiMincho(
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
                style: AppTheme.jostTabular(
                  color: page.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.0,
                ),
              ),

              const SizedBox(height: 14),

              Text(
                page.title,
                style: AppTheme.shipporiMincho(
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

// ─────────────────────────────────────────────────────────────────────────────
// Flat Hanko (_OnboardingScreenState._printRoom)
// ─────────────────────────────────────────────────────────────────────────────

/// How wide the words may run: a phone uses all of it, a wide window keeps
/// the column readable.
const double _kPrintedMeasure = 480;

/// The copy's line breaks were set for the old 50 px titles; in Hanko the
/// words flow and wrap whole wherever the width (or text size) needs.
String _flow(String s) => s.replaceAll('\n', ' ');

/// One page's column: the gutter, the measure, and room to scroll when a
/// large text size makes it taller than the screen.
class _PrintedColumn extends StatelessWidget {
  const _PrintedColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, 48, AppTheme.hankoGutter, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kPrintedMeasure),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
      );
}

/// The page's tag, its Mincho heading, the screen's one rule, and the
/// words under it, shared by every page.
class _PrintedHeading extends StatelessWidget {
  const _PrintedHeading({
    required this.tag,
    required this.title,
    required this.body,
  });

  final String tag;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tag,
            style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoLabelSize,
              weight: FontWeight.w500,
              color: AppTheme.hankoStone,
              letterSpacing: 1.6,
              height: 1.4,
              tabular: true,
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              title,
              style: AppTheme.hankoSerif(
                fontSize: AppTheme.hankoDisplaySize,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SizedBox(
            width: double.infinity,
            height: 1,
            child: ColoredBox(color: AppTheme.hankoHairline),
          ),
          const SizedBox(height: 20),
          Text(
            body,
            style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoSectionSize,
              color: AppTheme.hankoStone,
              height: 1.6,
            ),
          ),
        ],
      );
}

class _PrintedPage extends StatelessWidget {
  const _PrintedPage({required this.page, required this.fadeAnim});

  final _PageData page;
  final Animation<double> fadeAnim;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: fadeAnim,
        child: SafeArea(
          bottom: false,
          child: _PrintedColumn(
            children: [
              // The page's icon on a sumi 3 tile: washi, no colour
              ExcludeSemantics(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.hankoSumi3,
                    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  ),
                  child: Icon(page.icon, color: AppTheme.hankoWashi, size: 28),
                ),
              ),
              const SizedBox(height: 32),
              _PrintedHeading(
                tag: page.tag,
                title: _flow(page.title),
                body: _flow(page.subtitle),
              ),
            ],
          ),
        ),
      );
}

class _PrintedImportPage extends StatelessWidget {
  const _PrintedImportPage({
    required this.fadeAnim,
    required this.selectedImport,
    required this.onSelect,
  });

  final Animation<double> fadeAnim;
  final String? selectedImport;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: fadeAnim,
        child: SafeArea(
          bottom: false,
          child: _PrintedColumn(
            children: [
              // The mark, with its flash (hanj_cut.png is the 48 px-and-up cut)
              Image.asset(
                'assets/images/hanj_cut.png',
                width: 56,
                height: 56,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 32),
              const _PrintedHeading(
                tag: 'IMPORT',
                title: 'Bring Your List Along',
                body: 'Already tracking on AniList or MAL? '
                    'We’ll import your list after you sign in.',
              ),
              const SizedBox(height: 28),
              _PrintedImportOption(
                label: 'Import from AniList',
                sublabel: 'anilist.co',
                selected: selectedImport == 'anilist',
                onTap: () => onSelect(
                  selectedImport == 'anilist' ? null : 'anilist',
                ),
              ),
              const SizedBox(height: 12),
              _PrintedImportOption(
                label: 'Import from MyAnimeList',
                sublabel: 'myanimelist.net',
                selected: selectedImport == 'mal',
                onTap: () => onSelect(
                  selectedImport == 'mal' ? null : 'mal',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                selectedImport == null
                    ? 'Or tap Get Started to skip — you can import later in Settings.'
                    : 'We’ll remind you to complete the import once you’re in.',
                style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  color: AppTheme.hankoAsh,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
}

/// An import choice: a sumi 2 panel, washi keyline and a washi check when
/// chosen; tapping it again clears it, as before. One button for a screen
/// reader, with its chosen state, and keyboard focus shown by a washi ring.
class _PrintedImportOption extends StatefulWidget {
  const _PrintedImportOption({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PrintedImportOption> createState() => _PrintedImportOptionState();
}

class _PrintedImportOptionState extends State<_PrintedImportOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final selected = widget.selected;
    final radius = BorderRadius.circular(AppTheme.hankoRadius);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '${widget.label}, ${widget.sublabel}',
      child: _PrintedFocusRing(
        on: _focused,
        child: Material(
          color: AppTheme.hankoSumi2,
          borderRadius: radius,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (v) => setState(() => _focused = v),
            splashFactory: NoSplash.splashFactory,
            highlightColor: AppTheme.hankoPressWash,
            hoverColor: AppTheme.hankoPressWash,
            borderRadius: radius,
            child: ExcludeSemantics(
              child: AnimatedContainer(
                duration:
                    still ? Duration.zero : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                constraints: const BoxConstraints(minHeight: 64),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: selected
                        ? AppTheme.hankoWashi
                        : AppTheme.hankoSumi2,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.label,
                            style: AppTheme.hankoSans(
                              weight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.sublabel,
                            style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              color: AppTheme.hankoStone,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Its room is kept, so choosing never moves the words
                    Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: selected
                          ? AppTheme.hankoWashi
                          : const Color(0x00000000),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where you are: washi for this page, edge for the others, Hanko's 2 px
/// corners. Read out as one line ("Page 2 of 5").
class _PrintedPageMarks extends StatelessWidget {
  const _PrintedPageMarks({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Page ${current + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            count,
            (i) => AnimatedContainer(
              duration:
                  still ? Duration.zero : const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: current == i ? 16 : 6,
              height: 4,
              decoration: BoxDecoration(
                color:
                    current == i ? AppTheme.hankoWashi : AppTheme.hankoEdge,
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Next / Get Started: the washi main action (sumi words, 2 px corners,
/// no ripple), touched at 48 or more, with keyboard focus shown by a washi
/// ring outside it.
class _PrintedMainAction extends StatefulWidget {
  const _PrintedMainAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_PrintedMainAction> createState() => _PrintedMainActionState();
}

class _PrintedMainActionState extends State<_PrintedMainAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.hankoRadius);
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      child: _PrintedFocusRing(
        on: _focused,
        child: Material(
          color: AppTheme.hankoWashi,
          borderRadius: radius,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (v) => setState(() => _focused = v),
            splashFactory: NoSplash.splashFactory,
            highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
            hoverColor: AppTheme.hankoSumi.withValues(alpha: 0.05),
            borderRadius: radius,
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppTheme.hankoTouch,
                  minHeight: AppTheme.hankoTouch,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoListTitleSize,
                            weight: FontWeight.w600,
                            color: AppTheme.hankoSumi,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded,
                            color: AppTheme.hankoSumi, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Skip: stone words, no fill, touched at 48, the press a washi wash.
class _PrintedTextAction extends StatefulWidget {
  const _PrintedTextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_PrintedTextAction> createState() => _PrintedTextActionState();
}

class _PrintedTextActionState extends State<_PrintedTextAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.hankoRadius);
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      child: _PrintedFocusRing(
        on: _focused,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (v) => setState(() => _focused = v),
            splashFactory: NoSplash.splashFactory,
            highlightColor: AppTheme.hankoPressWash,
            hoverColor: AppTheme.hankoPressWash,
            borderRadius: radius,
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppTheme.hankoTouch,
                  minHeight: AppTheme.hankoTouch,
                ),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      widget.label,
                      style: AppTheme.hankoSans(
                        weight: FontWeight.w500,
                        color: AppTheme.hankoStone,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keyboard focus on a printed control, as hanko_board.dart's ring: 2 px
/// washi just outside it, a pixel clear, its room always kept.
class _PrintedFocusRing extends StatelessWidget {
  const _PrintedFocusRing({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
            color: on ? AppTheme.hankoWashi : const Color(0x00000000),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius + 3),
        ),
        child: Padding(padding: const EdgeInsets.all(3), child: child),
      );
}
