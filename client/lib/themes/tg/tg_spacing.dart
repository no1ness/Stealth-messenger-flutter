import 'package:stealth/logging/logger.dart';

class TgSpacing {
  TgSpacing._() {
    Logger.debug('TgSpacing: 6-tier scale created');
  }

  // Base scale — rem-based 6-tier from telegram-tt
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
  static const double massive = 64;

  // Border radii (telegram-tt: --border-radius-*)
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusRound = 999;

  // UI element sizes
  static const double buttonHeight = 44;
  static const double buttonHeightSmall = 32;
  static const double iconSm = 20;
  static const double iconMd = 24;
  static const double iconLg = 32;
  static const double bottomBarOverlap = 80;
  static const double screenEdge = 16;
}
