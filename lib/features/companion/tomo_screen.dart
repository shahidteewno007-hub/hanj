// tomo_screen.dart
//
// Chat screen for Loki, the anime companion. Text-only.
// Styled to match Hanj's dark editorial aesthetic. Assistant replies render
// lightweight markdown (bold / italic / bullet lists) so they read cleanly.
//
// Open it with:
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const TomoScreen()));

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'tomo_service.dart';

// Brand tokens (kept local so this file drops in anywhere).
const _kBg     = Color(0xFF0A0A0A);
const _kPanel  = Color(0xFF141312);
const _kIvory  = Color(0xFFF3EEE7);
const _kCoral  = Color(0xFFF97316);
const _kCoral2 = Color(0xFFE8624A);
const _kMuted  = Color(0xFF6B6B6B);
const _kLine   = Color(0x14F3EEE7);

class TomoScreen extends StatefulWidget {
  const TomoScreen({super.key});
  @override
  State<TomoScreen> createState() => _TomoScreenState();
}

class _TomoScreenState extends State<TomoScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<TomoMessage> _messages = [];
  bool _sending = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _controller.addListener(() => setState(() {})); // toggle send-button state
  }

  Future<void> _bootstrap() async {
    try {
      final history = await TomoService.instance.loadHistory();
      if (mounted) {
        setState(() {
          _messages.addAll(history);
          _loading = false;
        });
        _jumpToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _animateToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final userMsg = TomoMessage(role: 'user', text: text, ts: now);
    final historyForApi = List<TomoMessage>.from(_messages);

    setState(() {
      _messages.add(userMsg);
      _controller.clear();
      _sending = true;
    });
    _animateToBottom();

    try {
      final res = await TomoService.instance
          .send(message: text, history: historyForApi);
      if (!mounted) return;
      setState(() {
        _messages.add(TomoMessage(
          role: 'assistant',
          text: res.reply,
          ts: DateTime.now().millisecondsSinceEpoch,
        ));
        _sending = false;
      });
      _animateToBottom();
    } on FirebaseFunctionsException catch (e) {
      _appendError(e.code == 'resource-exhausted'
          ? (e.message ?? "That's all for today — catch you tomorrow!")
          : (e.message ?? 'Loki had a hiccup. Try again.'));
    } catch (_) {
      _appendError('Something went wrong reaching me. Try again in a sec.');
    }
  }

  void _appendError(String msg) {
    if (!mounted) return;
    setState(() {
      _messages.add(TomoMessage(
        role: 'assistant',
        text: msg,
        ts: DateTime.now().millisecondsSinceEpoch,
      ));
      _sending = false;
    });
    _animateToBottom();
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied', style: GoogleFonts.dmSans(color: _kIvory)),
        backgroundColor: const Color(0xFF1A1A18),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _kCoral, strokeWidth: 2,
                      ),
                    )
                  : (_messages.isEmpty ? _buildEmpty() : _buildList()),
            ),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kLine)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: _kIvory),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [_kCoral, _kCoral2]),
              boxShadow: [
                BoxShadow(color: _kCoral.withOpacity(0.4), blurRadius: 12, spreadRadius: -2),
              ],
            ),
            alignment: Alignment.center,
            // The fox glyph falls back to a platform CJK font on purpose:
            // DM Sans has no CJK coverage. Forcing Noto Serif JP here fetched
            // a 4 MB face to draw this one character. See WEB.md 3.3.
            child: Text('狐',
                style: GoogleFonts.dmSans(
                    color: _kBg, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Loki',
                    style: GoogleFonts.playfairDisplay(
                        color: _kIvory, fontSize: 20, fontWeight: FontWeight.w700)),
                Text('your anime companion',
                    style: GoogleFonts.spaceGrotesk(
                        color: _kMuted, fontSize: 11, letterSpacing: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    final prompts = const [
      "What should I watch next based on my taste?",
      "Catch me up on anime news this week",
      "Sell me on something from my Plan to Watch",
      "Who's the best character in what I'm watching?",
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Center(
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [_kCoral, _kCoral2]),
              boxShadow: [
                BoxShadow(color: _kCoral.withOpacity(0.35), blurRadius: 24, spreadRadius: -4),
              ],
            ),
            alignment: Alignment.center,
            // The fox glyph falls back to a platform CJK font on purpose:
            // DM Sans has no CJK coverage. Forcing Noto Serif JP here fetched
            // a 4 MB face to draw this one character. See WEB.md 3.3.
            child: Text('狐',
                style: GoogleFonts.dmSans(
                    color: _kBg, fontSize: 34, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 22),
        Text('Hey, I\u2019m Loki.',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
                color: _kIvory, fontSize: 26, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'I know your list and I\u2019ve seen everything. Ask me about what you\u2019re watching, what\u2019s airing, theories \u2014 anything. I won\u2019t spoil you.',
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(color: _kMuted, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 30),
        ...prompts.map(_suggestionChip),
      ],
    );
  }

  Widget _suggestionChip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _send(text),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _kPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kLine),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, size: 15, color: _kCoral),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: GoogleFonts.dmSans(color: _kIvory, fontSize: 13.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Message list ─────────────────────────────────────────────────────────
  Widget _buildList() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (_sending && i == _messages.length) return const _TypingBubble();
        final m = _messages[i];
        return _Bubble(message: m, onLongPress: () => _copy(m.text));
      },
    );
  }

  // ── Composer ───────────────────────────────────────────────────────────────
  Widget _buildComposer() {
    final canSend = _controller.text.trim().isNotEmpty && !_sending;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12, 10, 12, 10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kLine)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _kPanel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _kLine),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                style: GoogleFonts.dmSans(color: _kIvory, fontSize: 15),
                cursorColor: _kCoral,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Talk to Loki\u2026',
                  hintStyle: GoogleFonts.dmSans(color: _kMuted, fontSize: 15),
                  filled: false,
                  fillColor: Colors.transparent,
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: canSend ? () => _send() : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44, height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: canSend
                    ? const LinearGradient(colors: [_kCoral, _kCoral2])
                    : null,
                color: canSend ? null : _kPanel,
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                color: canSend ? _kBg : _kMuted,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── A single message bubble ────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final TomoMessage message;
  final VoidCallback onLongPress;
  const _Bubble({required this.message, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [_kCoral, _kCoral2]),
              ),
              alignment: Alignment.center,
              // The fox glyph falls back to a platform CJK font on purpose:
              // DM Sans has no CJK coverage. Forcing Noto Serif JP here fetched
              // a 4 MB face to draw this one character. See WEB.md 3.3.
              child: Text('狐',
                  style: GoogleFonts.dmSans(
                      color: _kBg, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.74,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: isUser ? null : _kPanel,
                  gradient: isUser
                      ? const LinearGradient(colors: [_kCoral, _kCoral2])
                      : null,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: isUser ? null : Border.all(color: _kLine),
                ),
                child: isUser
                    ? Text(
                        message.text,
                        style: GoogleFonts.dmSans(
                          color: _kBg, fontSize: 14.5, height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : _MarkdownText(message.text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Lightweight markdown renderer for Loki's replies ─────────────────────────
// Handles: **bold**, *italic* / _italic_, `code`, and - / • bullet lines.
// Deliberately small — no package dependency, tuned for chat-length text.
class _MarkdownText extends StatelessWidget {
  final String raw;
  const _MarkdownText(this.raw);

  static final _inline = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|_[^_]+_|`[^`]+`)');

  TextSpan _spanForLine(String line) {
    final children = <TextSpan>[];
    int idx = 0;
    for (final m in _inline.allMatches(line)) {
      if (m.start > idx) {
        children.add(TextSpan(text: line.substring(idx, m.start)));
      }
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        children.add(TextSpan(
          text: tok.substring(2, tok.length - 2),
          style: const TextStyle(fontWeight: FontWeight.w700, color: _kIvory),
        ));
      } else if (tok.startsWith('`')) {
        children.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: GoogleFonts.spaceGrotesk(
              color: _kCoral, fontSize: 13.5, fontWeight: FontWeight.w500),
        ));
      } else {
        // *italic* or _italic_
        children.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      }
      idx = m.end;
    }
    if (idx < line.length) children.add(TextSpan(text: line.substring(idx)));
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.dmSans(
      color: _kIvory, fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w400,
    );
    final lines = raw.split('\n');
    final widgets = <Widget>[];

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      final trimmed = line.trimLeft();
      final isBullet = trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('• ');

      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8)); // paragraph gap
        continue;
      }

      if (isBullet) {
        final content = trimmed.replaceFirst(RegExp(r'^[-*•]\s+'), '');
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7, right: 8, left: 2),
                child: Container(
                  width: 4, height: 4,
                  decoration: const BoxDecoration(
                      color: _kCoral, shape: BoxShape.circle),
                ),
              ),
              Expanded(
                child: RichText(text: _spanForLine(content).copyWith(style: base)),
              ),
            ],
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: RichText(text: _spanForLine(line).copyWith(style: base)),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }
}

extension _SpanStyle on TextSpan {
  TextSpan copyWith({TextStyle? style}) =>
      TextSpan(text: text, children: children, style: style ?? this.style);
}

// ── Animated "Loki is typing" bubble ─────────────────────────────────────────
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_kCoral, _kCoral2]),
            ),
            alignment: Alignment.center,
            // The fox glyph falls back to a platform CJK font on purpose:
            // DM Sans has no CJK coverage. Forcing Noto Serif JP here fetched
            // a 4 MB face to draw this one character. See WEB.md 3.3.
            child: Text('狐',
                style: GoogleFonts.dmSans(
                    color: _kBg, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _kPanel,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: _kLine),
            ),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final t = (_c.value + i * 0.2) % 1.0;
                    final o = 0.3 + 0.7 * (t < 0.5 ? t * 2 : (1 - t) * 2);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: Opacity(
                        opacity: o,
                        child: Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: _kCoral,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
