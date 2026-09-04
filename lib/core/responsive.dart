import 'package:flutter/material.dart';

class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1024;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  static double getWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double getHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  // Grid columns based on screen size
  static int getGridColumns(BuildContext context) {
    if (isMobile(context)) return 2;
    if (isTablet(context)) return 3;
    return 3; // Desktop
  }

  // Horizontal list card width
  static double getCardWidth(BuildContext context) {
    if (isMobile(context)) return 140;
    if (isTablet(context)) return 160;
    return 160; // Desktop
  }

  // Padding values
  static double getHorizontalPadding(BuildContext context) {
    if (isMobile(context)) return 12;
    if (isTablet(context)) return 16;
    return 16; // Desktop
  }

  static double getVerticalPadding(BuildContext context) {
    if (isMobile(context)) return 12;
    if (isTablet(context)) return 16;
    return 20; // Desktop
  }

  // Font size scaling
  static double scaleFontSize(BuildContext context, double baseSize) {
    if (isMobile(context)) return baseSize * 0.9;
    return baseSize;
  }

  // Avatar size
  static double getAvatarSize(BuildContext context) {
    if (isMobile(context)) return 80;
    if (isTablet(context)) return 90;
    return 100; // Desktop
  }

  // Bottom nav bar height
  static double getBottomNavHeight(BuildContext context) {
    if (isMobile(context)) return 60;
    return 70; // Desktop/Tablet
  }
}
