import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import 'arcs_screen.dart';
import 'soulmatch_screen.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  final _firestoreService = FirestoreService();
  final _friendCodeController = TextEditingController();
  
  String? _myShareCode;
  Map<String, dynamic>? _comparisonData;
  bool _isComparing = false;

  // ── Compare lists is hidden ────────────────────────────────
  // _compareWithFriend never looks the code up: _simulateComparison returns
  // a made-up "Demo Friend" at 60% overlap whatever is typed. The section's
  // code is intact below; set this to true once it compares a real list.
  // With the button hidden, _comparisonData stays null, so the results block
  // can't show either. The Soulmatch banner on this screen is the real
  // comparison, and takes the same share code.
  static const bool _compareEnabled = false;

  @override
  void initState() {
    super.initState();
    _generateMyShareCode();
  }

  @override
  void dispose() {
    _friendCodeController.dispose();
    super.dispose();
  }

  void _generateMyShareCode() {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user != null) {
      final raw = user.uid.replaceAll('-', '').toUpperCase();
      setState(() {
        _myShareCode = raw.length >= 8 ? raw.substring(0, 8) : raw.padRight(8, '0');
      });
    }
  }

  Future<void> _compareWithFriend() async {
    if (_friendCodeController.text.trim().isEmpty) {
      _showSnackBar('Please enter a friend code', AppTheme.error);
      return;
    }

    setState(() => _isComparing = true);

    try {
      final friendCode = _friendCodeController.text.trim().toUpperCase();
      
      // Find user with this share code (in real app, you'd have a shareCode field)
      // For now, we'll simulate with mock data
      final myList = await _firestoreService.getAnimeList().first;
      if (!mounted) return;
      
      // Simulate friend's list (in real app, fetch from Firestore)
      final comparison = _simulateComparison(myList.docs);
      
      setState(() {
        _comparisonData = comparison;
        _isComparing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isComparing = false);
      _showSnackBar('Failed to compare lists', AppTheme.error);
    }
  }

  Map<String, dynamic> _simulateComparison(List<QueryDocumentSnapshot> myDocs) {
    // Simulate comparison (in real app, this would compare with actual friend data)
    final myAnimeIds = myDocs.map((d) => (d.data() as Map)['animeId']).toSet();
    
    // Mock: assume friend has 60% overlap
    final commonCount = (myAnimeIds.length * 0.6).round();
    final compatibility = (commonCount / myAnimeIds.length * 100).round();
    
    return {
      'friendName': 'Demo Friend',
      'myTotal': myAnimeIds.length,
      'friendTotal': myAnimeIds.length + 5,
      'inCommon': commonCount,
      'compatibility': compatibility,
      'commonAnime': myDocs.take(commonCount).map((d) {
        final data = d.data() as Map<String, dynamic>;
        return {
          'title': data['title'],
          'imageUrl': data['imageUrl'],
        };
      }).toList(),
    };
  }

  /// In Hanko the note takes the theme's own snack bar, washi words on a
  /// sumi step: the green and the error pink it was given measured about
  /// 2.7 and 2.3:1 under washi, and colour isn't what says it worked.
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _preHanko ? color : null,
        behavior: SnackBarBehavior.floating,
        shape: _preHanko
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            : null,
      ),
    );
  }

  void _copyShareCode() {
    if (_myShareCode != null) {
      Clipboard.setData(ClipboardData(text: _myShareCode!));
      _showSnackBar(_preHanko ? 'Share code copied!' : 'Share code copied.',
          AppTheme.success);
    }
  }

  /// The screen before Hanko (question 73): a coral and a purple gradient
  /// banner with emoji for Arcs and Soulmatch, and the share code in a
  /// rounded card in alternating coral and ivory pairs. Kept switched off as
  /// design history; _buildPreHanko() holds it.
  static const bool _preHanko = false;

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_sharp),
          color: AppTheme.hankoWashi,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Social', style: AppTheme.hankoSerif(fontSize: 20)),
      ),
      body: SingleChildScrollView(
        padding: _preHanko
            ? const EdgeInsets.all(24)
            : const EdgeInsets.fromLTRB(
                AppTheme.hankoGutter, 16, AppTheme.hankoGutter, 40),
        // On a wide window the page keeps Profile's reading column, hung on
        // the left, instead of stretching rows and the code across it.
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: _preHanko ? double.infinity : Responsive.proseMaxWidth),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_preHanko) ..._buildPreHanko() else ..._buildHanko(),

            // Compare Lists Section (hidden, see _compareEnabled)
            if (_compareEnabled) ...[
              const SizedBox(height: 32),

              Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppTheme.secondary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Compare lists', style: AppTheme.serif(fontSize: 22, weight: FontWeight.w600)),
                ],
              ),

              const SizedBox(height: 16),

              TextField(
                controller: _friendCodeController,
                decoration: InputDecoration(
                  hintText: 'Enter friend\'s code...',
                  prefixIcon: const Icon(Icons.person_add_rounded),
                  filled: true,
                  fillColor: AppTheme.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isComparing ? null : _compareWithFriend,
                  icon: _isComparing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.compare_rounded),
                  label: Text(_isComparing ? 'Comparing...' : 'Compare'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.textInverse, // sumi on coral, 5.64:1
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],

            // Comparison Results
            if (_comparisonData != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Column(
                  children: [
                    // Compatibility Score
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.success.withValues(alpha: 0.3),
                            AppTheme.primaryLight.withValues(alpha: 0.3),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${_comparisonData!['compatibility']}%',
                            style: Theme.of(context)
                                .textTheme
                                .displayLarge
                                ?.copyWith(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text('Compatibility',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            'with ${_comparisonData!['friendName']}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ComparisonStat(
                          label: 'Your List',
                          value: '${_comparisonData!['myTotal']}',
                          color: AppTheme.primary,
                        ),
                        _ComparisonStat(
                          label: 'In Common',
                          value: '${_comparisonData!['inCommon']}',
                          color: AppTheme.success,
                        ),
                        _ComparisonStat(
                          label: 'Their List',
                          value: '${_comparisonData!['friendTotal']}',
                          color: AppTheme.secondary,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Common Anime
                    if (_comparisonData!['commonAnime'].isNotEmpty) ...[
                      const Divider(),
                      const SizedBox(height: 16),
                      Text('Anime in Common',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 80,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _comparisonData!['commonAnime'].length,
                          itemBuilder: (context, index) {
                            final anime =
                                _comparisonData!['commonAnime'][index];
                            return Container(
                              width: 60,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.success),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  anime['imageUrl'] ?? '',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stack) =>
                                      Container(
                                    color: AppTheme.surfaceLight,
                                    child: const Icon(Icons.image_outlined,
                                        color: AppTheme.textMuted),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
            ),
          ),
        ),
      ),
    );
  }

  /// Social in Hanko (question 73). Your share code first, since it is what
  /// this screen holds: the code in washi Jost, the privacy line that says
  /// what it shows, and Copy code as the screen's one washi action. Then,
  /// below the screen's one hairline, the ways on as Profile's quiet rows:
  /// Soulmatch, where you type a friend's code, and Arcs, whose page says
  /// "Arcs are coming" while Arcs is gated (arcs_screen.dart), so its line
  /// says so too. Gone: the coral and purple gradient banners and their
  /// emoji, and the coral pairs in the code; coral is only your seal now.
  List<Widget> _buildHanko() {
    final code = _myShareCode;
    return [
      Semantics(
        header: true,
        child: Text('Your share code',
            style: AppTheme.hankoSerif(
                fontSize: AppTheme.hankoSectionSize, height: 1.3)),
      ),
      const SizedBox(height: 14),
      code == null
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.hankoStone),
            )
          : _HankoShareCode(code),
      const SizedBox(height: 12),
      Text(
        "Friends with this code can see what you're watching and how your lists compare.",
        style: AppTheme.hankoSans(
            fontSize: AppTheme.hankoMetaSize,
            color: AppTheme.hankoStone,
            height: 1.5),
      ),
      const SizedBox(height: 20),
      _HankoCopyButton(onTap: code == null ? null : _copyShareCode),
      const SizedBox(height: 32),
      const ColoredBox(
        color: AppTheme.hankoHairline,
        child: SizedBox(height: 1, width: double.infinity),
      ),
      const SizedBox(height: 10),
      _SocialRow(
        icon: Icons.join_inner_sharp,
        title: 'Soulmatch',
        line: 'Enter a friend\'s code to compare your taste',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SoulmatchScreen())),
      ),
      const SizedBox(height: 4),
      _SocialRow(
        icon: Icons.groups_2_sharp,
        title: 'Arcs',
        line: 'Communities around the shows you love. Coming soon',
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ArcsScreen())),
      ),
    ];
  }

  /// The top of the screen before Hanko (_preHanko): the Arcs and Soulmatch
  /// banners and the share-code card.
  List<Widget> _buildPreHanko() {
    return [
      // ── Arcs banner ───────────────────────────────────
      GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ArcsScreen())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary.withValues(alpha: 0.2),
                const Color(0xFF1A0A06),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Text('🏛️', style: TextStyle(fontSize: 36)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Arcs',
                        style: AppTheme.serif(
                            fontSize: 18, weight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Join communities, start discussions,\nfind your people.',
                      style: AppTheme.sans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.primary),
            ],
          ),
        ),
      ),

      // ── Soulmatch banner ──────────────────────────────
      GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SoulmatchScreen())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF9B59B6).withValues(alpha: 0.2),
                const Color(0xFF1A0820),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF9B59B6).withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Text('🪞', style: TextStyle(fontSize: 36)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Soulmatch',
                        style: AppTheme.serif(
                            fontSize: 18, weight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Find your anime soulmate.\nCompare taste with friends.',
                      style: AppTheme.sans(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF9B59B6)),
            ],
          ),
        ),
      ),
      // My Share Code Card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF121110),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('H', style: AppTheme.serif(fontSize: 16, weight: FontWeight.w700).copyWith(color: AppTheme.primary)),
                const SizedBox(width: 6),
                Text('· YOUR SHARE CODE', style: AppTheme.mono(fontSize: 10, color: AppTheme.primary, letterSpacing: 1.2)),
              ],
            ),
            const SizedBox(height: 20),
            _myShareCode == null
                ? const CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primary)
                : _buildCodeDisplay(_myShareCode!),
            const SizedBox(height: 14),
            Text(
              "Friends with this code can see what you're watching and how your lists compare.",
              style: AppTheme.sans(fontSize: 13, color: AppTheme.textMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _copyShareCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(color: AppTheme.textPrimary, borderRadius: BorderRadius.circular(30)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.copy_rounded, color: AppTheme.textInverse, size: 16),
                      const SizedBox(width: 8),
                      Text('Copy code', style: AppTheme.sans(fontSize: 14, weight: FontWeight.w600, color: AppTheme.textInverse)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildCodeDisplay(String code) {
    final safe = code.padRight(8, '0');
    final p1 = safe.substring(0, 4);
    final p2 = safe.substring(4, 8);
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800,
            fontFamily: 'monospace', letterSpacing: 4),
        children: [
          TextSpan(text: p1.substring(0, 2),
              style: const TextStyle(color: Color(0xFFF5F0E8))),
          TextSpan(text: p1.substring(2),
              style: const TextStyle(color: Color(0xFFE8624A))),
          const TextSpan(text: ' ',
              style: TextStyle(color: Color(0xFFF5F0E8))),
          TextSpan(text: p2.substring(0, 2),
              style: const TextStyle(color: Color(0xFFE8624A))),
          TextSpan(text: p2.substring(2),
              style: const TextStyle(color: Color(0xFFF5F0E8))),
        ],
      ),
    );
  }
}

class _ComparisonStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ComparisonStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Your share code as Hanko sets it: washi Jost 500 at 34, tabular, two
/// groups of four, in one colour (the coral and ivory pairs were decoration,
/// and coral is your seal now). It wraps between the groups at large text
/// rather than overflowing. A screen reader hears it a character at a time.
class _HankoShareCode extends StatelessWidget {
  const _HankoShareCode(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final safe = code.padRight(8, '0');
    final shown = '${safe.substring(0, 4)} ${safe.substring(4, 8)}';
    return Semantics(
      label: 'Your share code: ${safe.split('').join(' ')}',
      excludeSemantics: true,
      child: Text(
        shown,
        style: AppTheme.hankoSans(
          fontSize: 34,
          weight: FontWeight.w500,
          letterSpacing: 3,
          height: 1.2,
          tabular: true,
        ),
      ),
    );
  }
}

/// Copy code, the screen's one main action as Hanko draws it (Detail's
/// _HankoMainAction): a washi tile with sumi words, 15.34:1, 2 px corners,
/// at least 48 px, pressed with a sumi wash and no ripple.
class _HankoCopyButton extends StatelessWidget {
  const _HankoCopyButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Copy code',
      excludeSemantics: true,
      child: Material(
        color: AppTheme.hankoWashi,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
          hoverColor: AppTheme.hankoSumi.withValues(alpha: 0.05),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minWidth: AppTheme.hankoTouch,
                minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.copy_sharp,
                      size: 20, color: AppTheme.hankoSumi),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Copy code',
                      style: AppTheme.hankoSans(
                        fontSize: 15,
                        weight: FontWeight.w600,
                        color: AppTheme.hankoSumi,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A way on from Social, drawn as Profile's quiet rows are (its _EntryRow,
/// private to that file): an icon in stone, the name in Jost 15 500 washi,
/// a line in Jost 13 stone and a chevron, no box and no colour of its own,
/// at least 56 px tall, pressed with the 8% washi wash.
class _SocialRow extends StatelessWidget {
  const _SocialRow({
    required this.icon,
    required this.title,
    required this.line,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $line',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 22, color: AppTheme.hankoStone),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: AppTheme.hankoSans(
                              fontSize: 15,
                              weight: FontWeight.w500,
                              height: 1.25)),
                      const SizedBox(height: 2),
                      Text(line,
                          style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: AppTheme.hankoStone,
                            height: 1.3,
                          )),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right_sharp,
                    size: 20, color: AppTheme.hankoStone),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

