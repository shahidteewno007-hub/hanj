import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInAuthenticationEvent, GoogleSignInAuthenticationEventSignIn;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/google_g_logo.dart';

import '../../services/auth_service.dart';
import '../../services/anilist_service.dart';
import '../../models/anime_model.dart';
import 'signup_screen.dart';
import 'google_button_stub.dart'
    if (dart.library.js_interop) 'google_button_web.dart' as google_button;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _authService      = AuthService();
  final _aniListService   = AnilistService();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe      = false;
  bool _isLoading       = false;
  String? _errorMessage;

  /// Web only — the Google rendered button's result stream. Null on Android.
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSub;

  List<Anime> _posterAnime        = [];
  List<AnimationController> _controllers = [];
  List<Animation<double>> _animations   = [];
  bool _postersReady = false;

  // ── Trending ticker ─────────────────────────────────────────
  late AnimationController _tickerCtrl;
  late Animation<double>   _tickerAnim;
  List<String> _trendingTitles = [];

  static const _bg     = Color(0xFF08050F);
  static const _coral  = Color(0xFFE8624A);
  static const _magenta = Color(0xFFCA2868);

  // ── More posters: fetch trending + popular ──────────────────
  static const _posterCount = 18;

  @override
  void initState() {
    super.initState();
    _tickerCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 20))
      ..repeat();
    _tickerAnim = Tween<double>(begin: 0, end: 1).animate(_tickerCtrl);
    _loadPosters();
    if (google_button.usesRenderedGoogleButton) _listenForWebGoogleSignIn();
  }

  /// Web only. Google's rendered button does not return a credential, so the
  /// result arrives on this stream instead. Never runs on Android, which keeps
  /// its programmatic flow untouched.
  Future<void> _listenForWebGoogleSignIn() async {
    try {
      final events = await _authService.webGoogleAuthEvents();
      _googleAuthSub = events.listen((event) async {
        if (event is! GoogleSignInAuthenticationEventSignIn) return;
        if (mounted) setState(() { _isLoading = true; _errorMessage = null; });
        try {
          await _authService.completeGoogleSignIn(event.user);
          // AuthWrapper's stream swaps to MainScreen on success.
        } catch (e) {
          if (mounted) setState(() => _errorMessage = e.toString());
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      });
    } catch (e) {
      // initialize() failing is the misconfigured-client-ID case. Say so
      // rather than leaving a button that silently does nothing.
      if (mounted) {
        setState(() => _errorMessage =
            'Google sign-in is unavailable. You can still sign in with email.');
      }
    }
  }

  @override
  void dispose() {
    _googleAuthSub?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    _tickerCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadPosters() async {
    // Start animations immediately with gradient placeholders
    _initAnimations();
    try {
      final results = await Future.wait([
        _aniListService.getTrending(),
        _aniListService.getPopular(),
      ]);
      if (!mounted) return;
      final combined = <Anime>{...results[0], ...results[1]}.toList();
      combined.shuffle(Random());
      setState(() {
        _posterAnime    = combined.take(_posterCount).toList();
        _trendingTitles = results[0].take(6).map((a) => a.title).toList();
      });
    } catch (_) {}
  }

  void _initAnimations() {
    final count = _posterAnime.isEmpty ? _posterCount : _posterAnime.length;
    _controllers = List.generate(count, (i) {
      final dur = Duration(milliseconds: 3500 + Random().nextInt(2000));
      return AnimationController(vsync: this, duration: dur)
        ..repeat(reverse: true);
    });
    _animations = _controllers.map((c) {
      final begin = -0.08 + Random().nextDouble() * 0.08;
      final end   = begin + 0.12 + Random().nextDouble() * 0.1;
      return Tween<double>(begin: begin, end: end).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();
    if (mounted) setState(() => _postersReady = true);
  }

  Future<void> _signIn() async {
    final email    = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final cred = await _authService.signInWithEmail(email, password);
      if (!mounted) return;
      if (cred != null) {
        // Auth state stream in AuthWrapper will swap to MainScreen automatically.
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final cred = await _authService.signInWithGoogle();
      if (!mounted) return;
      if (cred != null) {
        // Auth state stream in AuthWrapper will swap to MainScreen automatically.
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _forgotPassword() {
    final email = _emailController.text.trim();
    // Capture the messenger from the SCREEN's context, not the dialog's,
    // so it stays valid after the dialog is dismissed.
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) {
        final ctrl = TextEditingController(text: email);
        return AlertDialog(
          backgroundColor: const Color(0xFF130B22),
          title: const Text('Reset Password',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter your email',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _coral)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await _authService.sendPasswordResetEmail(ctrl.text);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Reset email sent!')),
                  );
                } catch (e) {
                  if (mounted) setState(() => _errorMessage = e.toString());
                }
              },
              child: const Text('Send', style: TextStyle(color: _coral)),
            ),
          ],
        );
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Full-screen animated poster grid
          if (_controllers.isNotEmpty) _buildPosterGrid(size),

          // Very light dark veil — just enough to read text
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _bg.withValues(alpha: 0.25),
                  _bg.withValues(alpha: 0.35),
                  _bg.withValues(alpha: 0.55),
                  _bg.withValues(alpha: 0.80),
                ],
                stops: const [0.0, 0.25, 0.55, 1.0],
              ),
            ),
          ),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: SizedBox(
                height: size.height - MediaQuery.of(context).padding.top,
                child: Column(
                  children: [
                    const SizedBox(height: 12),

                    // Trending ticker
                    _buildTrendingTicker(),

                    const Spacer(),
                    const Spacer(),

                    // Wordmark
                    _buildWordmark(),
                    const SizedBox(height: 6),
                    Text(
                      'WORLDS WORTH WATCHING',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 10,
                        letterSpacing: 3.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Glass login card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildGlassCard(),
                    ),

                    const SizedBox(height: 16),

                    // Google sign-in
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildGoogleButton(),
                    ),

                    const SizedBox(height: 20),

                    // Sign up link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'New here? ',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 14),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const SignupScreen())),
                          child: const Text(
                            'Create an account',
                            style: TextStyle(
                              color: _coral,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'ALSO CONSIDERED: kiseki · nagare · sora · hikari',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.18),
                        fontSize: 9,
                        letterSpacing: 1.2,
                      ),
                    ),

                    const Spacer(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Poster Grid ──────────────────────────────────────────────

  Widget _buildPosterGrid(Size size) {
    const cols   = 3;
    final gap    = 6.0;
    final cardW  = (size.width - gap * (cols + 1)) / cols;
    final cardH  = cardW * 1.55;
    final rows   = (_controllers.length / cols).ceil() + 1;

    return SizedBox.expand(
      child: Stack(
        children: List.generate(_controllers.length, (i) {
          final col   = i % cols;
          final row   = i ~/ cols;
          final x     = gap + col * (cardW + gap);
          final baseY = -cardH * 0.4 + row * (cardH + gap);

          // Alternate columns offset vertically for stagger effect
          final colOffset = col == 1 ? cardH * 0.3 : 0.0;

          return AnimatedBuilder(
            animation: _animations[i],
            builder: (_, child) => Positioned(
              left: x,
              top: baseY + colOffset + _animations[i].value * size.height * 0.15,
              child: child!,
            ),
            child: SizedBox(
              width: cardW,
              height: cardH,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _posterAnime.isNotEmpty && i < _posterAnime.length
                    ? CachedNetworkImage(
                        imageUrl: _posterAnime[i].imageUrl ?? '',
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => _gradientCard(i),
                      )
                    : _gradientCard(i),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _gradientCard(int i) {
    final colors = [
      [const Color(0xFF2D1B4E), const Color(0xFF6B2D6B)],
      [const Color(0xFF1A2A4E), const Color(0xFF2D5A8E)],
      [const Color(0xFF4E1B2D), const Color(0xFF8E2D4E)],
      [const Color(0xFF1B3A2D), const Color(0xFF2D6B4E)],
      [const Color(0xFF3A2A1B), const Color(0xFF6B4E2D)],
    ];
    final pair = colors[i % colors.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pair,
        ),
      ),
    );
  }

  // ── Trending ticker ──────────────────────────────────────────

  Widget _buildTrendingTicker() {
    final titles = _trendingTitles.isNotEmpty
        ? _trendingTitles
        : ['Crimson Veil', 'Hollow Tide', 'Petal Frequency', 'Twin Sunfall'];
    final text = titles.map((t) => t).join('  ·  ');

    return Row(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 16),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _coral,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '● TRENDING',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _tickerAnim,
              builder: (_, _) {
                return FractionalTranslation(
                  translation: Offset(-_tickerAnim.value, 0),
                  child: Text(
                    '$text  ·  $text',
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  // ── Wordmark ─────────────────────────────────────────────────

  Widget _buildWordmark() {
    return Column(
      children: [
        // Wing mark
        SizedBox(
          width: 48,
          height: 48,
          child: Image.asset(
            'assets/images/hanj_wing_transparent.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 16),
        // Hanj wordmark — "Ha" white, "n" coral italic, "j" white
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Ha',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w700,
                  height: 0.9,
                  letterSpacing: -2,
                ),
              ),
              TextSpan(
                text: 'n',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w700,
                  height: 0.9,
                  letterSpacing: -2,
                ),
              ),
              TextSpan(
                text: 'j',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w700,
                  height: 0.9,
                  letterSpacing: -2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Glass card ───────────────────────────────────────────────

  Widget _buildGoogleButton() {
    // Web must use Google's own rendered button — see google_button_web.dart.
    // The custom button below stays exactly as it is for Android.
    if (google_button.usesRenderedGoogleButton) {
      return Align(
        alignment: Alignment.center,
        child: SizedBox(
          height: 52,
          // GSI caps the button at 400px wide.
          child: google_button.buildGoogleSignInButton(width: 320),
        ),
      );
    }
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isLoading ? null : _handleGoogleSignIn,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Official multicolor Google G
              Container(
                width: 26, height: 26,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: const Center(child: GoogleGLogo(size: 18)),
              ),
              const SizedBox(width: 12),
              Text(
                'Continue with Google',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.14), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(
                controller: _emailController,
                hint: 'akira@hanj.app',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _passwordController,
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                obscure: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 12),

              // Remember me + Forgot
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? false),
                      activeColor: _coral,
                      side: const BorderSide(color: Colors.white38),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Remember me',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _forgotPassword,
                    child: Text('Forgot?',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 13)),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Error
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _coral.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: _coral, fontSize: 13)),
                ),
                const SizedBox(height: 12),
              ],

              // Sign in button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [_coral, _magenta]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Sign in',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded,
                                    color: Colors.white, size: 18),
                              ],
                            ),
                    ),
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.3), fontSize: 15),
          prefixIcon: Icon(icon,
              color: Colors.white.withValues(alpha: 0.4), size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        onSubmitted: (_) => _signIn(),
      ),
    );
  }

}
