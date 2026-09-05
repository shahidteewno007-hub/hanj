// Non-web fallback for the Google sign-in button.
//
// Android signs in programmatically via AuthService.signInWithGoogle() and
// keeps its own custom-styled button, so nothing here is ever rendered. This
// exists only to satisfy the conditional import in login_screen.dart.

import 'package:flutter/material.dart';

/// Never shown on mobile — the custom button in login_screen is used instead.
Widget buildGoogleSignInButton({double? width}) => const SizedBox.shrink();

/// False on mobile: the programmatic authenticate() flow works there.
bool get usesRenderedGoogleButton => false;
