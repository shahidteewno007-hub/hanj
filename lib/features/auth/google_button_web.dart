// Web implementation of the Google sign-in button.
//
// Google Identity Services will not accept a programmatic sign-in call from a
// browser — google_sign_in_web's supportsAuthenticate() is false and
// authenticate() throws UnimplementedError. The credential can only come from
// Google's own rendered button, so on web that is what the login screen shows.
//
// Imported via a conditional import (see google_button_stub.dart), matching the
// pattern already used for gal_mobile/gal_stub and trailer_launcher_web.

import 'package:flutter/material.dart';
// google_sign_in_web is google_sign_in's own web implementation, so it is
// always present in the dependency tree and in every web build. It is not
// declared in pubspec.yaml because that would mean choosing a version
// constraint, which the standing rules put off-limits. Suppressed rather than
// declared; worth formalising if this pattern spreads.
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_web/web_only.dart' as web_only;

/// Google's rendered sign-in button.
///
/// How far this can be styled toward Hanj's identity: **barely.**
/// GSIButtonConfiguration exposes only type, theme (outline / filledBlue /
/// filledBlack), size, text, shape (rectangular / pill), logo alignment, a
/// maximum width of 400px, and locale. There is no custom colour, no custom
/// font and no custom radius, so the coral (#E8624A) and DM Sans cannot be
/// applied. `outline` on the dark background is the closest of the three.
Widget buildGoogleSignInButton({double? width}) {
  return web_only.renderButton(
    configuration: web_only.GSIButtonConfiguration(
      // filledBlack, not outline: outline renders a white button, which on the
      // near-black login screen reads as a foreign element pasted on top.
      // Verified by rendering both. This is the closest of the three themes to
      // the app's palette — which is as close as GIS allows.
      theme: web_only.GSIButtonTheme.filledBlack,
      size: web_only.GSIButtonSize.large,
      text: web_only.GSIButtonText.continueWith,
      shape: web_only.GSIButtonShape.pill,
      logoAlignment: web_only.GSIButtonLogoAlignment.left,
      minimumWidth: width,
    ),
  );
}

/// True when the platform requires Google's rendered button rather than a
/// programmatic call.
bool get usesRenderedGoogleButton => true;
