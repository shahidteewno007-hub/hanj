import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme/app_theme.dart';

/// Hanj's legal pages (code batch 1, audit 7a items 4 and 5, LR-004).
///
/// The pages don't exist yet: their text is a later session's, approved by
/// Shahid word by word (Q174). So [live] is false and nothing here shows.
/// Once the four pages are published at these addresses, true shows the
/// legal rows in Profile's More sheet, the consent line under the sign-up
/// buttons on Sign in and Create account, and the deletion page's address
/// on Delete Account.
class LegalLinks {
  LegalLinks._();

  static const bool live = false;

  static const privacy = 'https://hanj.app/privacy';
  static const terms = 'https://hanj.app/terms';
  static const rules = 'https://hanj.app/rules';
  static const deleteAccount = 'https://hanj.app/delete-account';

  /// Opens a page in the browser. Never throws.
  static Future<void> open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }
}

/// "By continuing you confirm you are 13 or older and agree to the Terms
/// and the Privacy Policy." The two names open their pages. Shown only
/// when [LegalLinks.live]; the age is the audit's reading (LR-004) and is
/// Shahid's to confirm with the policy text.
class LegalConsentLine extends StatefulWidget {
  final Color color;
  final TextAlign textAlign;
  const LegalConsentLine({
    super.key,
    this.color = AppTheme.hankoStone,
    this.textAlign = TextAlign.center,
  });

  @override
  State<LegalConsentLine> createState() => _LegalConsentLineState();
}

class _LegalConsentLineState extends State<LegalConsentLine> {
  final _terms = TapGestureRecognizer()
    ..onTap = () => LegalLinks.open(LegalLinks.terms);
  final _privacy = TapGestureRecognizer()
    ..onTap = () => LegalLinks.open(LegalLinks.privacy);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!LegalLinks.live) return const SizedBox.shrink();
    final base = AppTheme.hankoSans(
        fontSize: AppTheme.hankoLabelSize, color: widget.color, height: 1.5);
    final link = base.copyWith(
        color: AppTheme.hankoWashi, decoration: TextDecoration.underline);
    return Text.rich(
      TextSpan(style: base, children: [
        const TextSpan(
            text: 'By continuing you confirm you are 13 or older and agree '
                'to the '),
        TextSpan(text: 'Terms', style: link, recognizer: _terms),
        const TextSpan(text: ' and the '),
        TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
        const TextSpan(text: '.'),
      ]),
      textAlign: widget.textAlign,
    );
  }
}
