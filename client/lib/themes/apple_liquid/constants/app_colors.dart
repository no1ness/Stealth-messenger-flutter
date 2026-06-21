import 'dart:ui';

class AppColors {
  AppColors._();

  // Primary Apple Blue
  static const Color systemBlue = Color(0xFF007AFF);
  static const Color systemBlueDark = Color(0xFF0A84FF);
  
  // System Grays (Apple Design)
  static const Color systemGray = Color(0xFF8E8E93);
  static const Color systemGray2 = Color(0xFFAEAEB2);
  static const Color systemGray3 = Color(0xFFC7C7CC);
  static const Color systemGray4 = Color(0xFFD1D1D6);
  static const Color systemGray5 = Color(0xFFE5E5EA);
  static const Color systemGray6 = Color(0xFFF2F2F7);
  
  // Dark Mode Grays
  static const Color darkGray = Color(0xFF1C1C1E);
  static const Color darkGray2 = Color(0xFF2C2C2E);
  static const Color darkGray3 = Color(0xFF3A3A3C);
  static const Color darkGray4 = Color(0xFF48484A);
  static const Color darkGray5 = Color(0xFF636366);
  static const Color darkGray6 = Color(0xFF8E8E93);
  
  // Semantic Colors
  static const Color systemGreen = Color(0xFF34C759);
  static const Color systemRed = Color(0xFFFF3B30);
  static const Color systemOrange = Color(0xFFFF9500);
  static const Color systemYellow = Color(0xFFFFCC00);
  static const Color systemPink = Color(0xFFFF2D55);
  static const Color systemPurple = Color(0xFFAF52DE);
  static const Color systemTeal = Color(0xFF5AC8FA);
  static const Color systemIndigo = Color(0xFF5856D6);
  
  // Stealth Backgrounds (темно-серые с синеватым оттенком)
  static const Color backgroundPrimary = Color(0xFF0A0E1A); // Очень темный синеватый
  static const Color backgroundSecondary = Color(0xFF151922); // Темно-серый с синим
  static const Color backgroundTertiary = Color(0xFF1E2330); // Средне-темный
  
  // Stealth Glass Effect Colors (с синеватым оттенком) - УСИЛЕНЫ
  static const Color glassLight = Color(0x70FFFFFF);      // Было 0x50, стало 0x70
  static const Color glassMedium = Color(0x40FFFFFF);     // Было 0x28, стало 0x40
  static const Color glassDark = Color(0x25FFFFFF);       // Было 0x15, стало 0x25
  static const Color glassUltraDark = Color(0x15FFFFFF);  // Было 0x0A, стало 0x15
  
  // Stealth Blue Tint для glass эффектов
  static const Color glassBlue = Color(0x30007AFF);
  static const Color glassPurple = Color(0x205856D6);
  
  // Stealth Background Gradients (темные с синеватым оттенком)
  static const List<Color> stealthGradient = [
    Color(0xFF0A0E1A), // Темно-синий
    Color(0xFF151922), // Темно-серый
    Color(0xFF0D1117), // Очень темный
  ];

  // Light-mode background fallback (accessibility / high-contrast variant).
  // Used by StealthAnimatedBackground when Theme.brightness == light — the
  // animated blur spots are dropped and we render a calm near-white wash
  // instead. Same warmth as the light scaffold (#F5F5F7) so cards sit on
  // a continuous canvas.
  static const List<Color> stealthGradientLight = [
    Color(0xFFF7F7FB), // near-white top, faint cool tint
    Color(0xFFEFEFF3), // mid
    Color(0xFFE7E7EB), // bottom — gentle vignette
  ];
  
  // Gradient Colors for Liquid Effect (более темные для stealth)
  static const List<Color> liquidGradient1 = [
    Color(0xFF007AFF),
    Color(0xFF5856D6),
  ];
  
  static const List<Color> liquidGradient2 = [
    Color(0xFFFF2D55),
    Color(0xFFFF9500),
  ];
  
  static const List<Color> liquidGradient3 = [
    Color(0xFF34C759),
    Color(0xFF5AC8FA),
  ];
  
  static const List<Color> liquidGradient4 = [
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
  ];
  
  // Stealth Accent Gradients
  static const List<Color> stealthAccent1 = [
    Color(0xFF1E3A8A), // Темно-синий
    Color(0xFF3B82F6), // Синий
  ];
  
  static const List<Color> stealthAccent2 = [
    Color(0xFF4C1D95), // Темно-фиолетовый
    Color(0xFF7C3AED), // Фиолетовый
  ];
  
  // Text Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF);
  static const Color textTertiary = Color(0x4DFFFFFF);
  static const Color textQuaternary = Color(0x26FFFFFF);
  
  // Border Colors
  static const Color separator = Color(0x29545458);
  static const Color separatorOpaque = Color(0xFF38383A);

  // Special Effects
  static const Color shadow = Color(0x33000000);
  static const Color shadowStrong = Color(0x66000000);

  // --------------------------------------------------------------
  // Semantic aliases — design-system v2 (do NOT inline raw colors
  // in new widgets; always go through a semantic alias when one
  // exists, so a future palette tweak does not require a per-file
  // sweep).
  // --------------------------------------------------------------

  /// White-ish base for text drawn on top of a glass surface.
  /// Equivalent to [textPrimary] but named for intent.
  static const Color textOnGlass = textPrimary;

  /// Hair-thin divider color suitable for `ListDivider` rows inside
  /// a glass-backgrounded list. Translucent — sits softly over any
  /// gradient.
  static const Color dividerSubtle = separator;

  /// Muted surface used by skeleton placeholders and empty-state
  /// backgrounds. Sits below glass but above the absolute dark.
  static const Color surfaceMuted = backgroundTertiary;

  // Status colors — semantic aliases over the iOS system palette.
  // Use these instead of `systemGreen/Red/Orange/Blue` so the
  // intent ("this is a success indicator", not "this is green")
  // travels with the code.
  static const Color statusSuccess = systemGreen;
  static const Color statusWarn = systemOrange;
  static const Color statusDanger = systemRed;
  static const Color statusInfo = systemBlue;

  // Dashboard tokens (Telegram-style dark palette)
  static const Color dashboardBg = Color(0xFF17212B);
  static const Color dashboardCard = Color(0xFF242F3D);
  static const Color dashboardText = Color(0xFFF5F5F5);
  static const Color dashboardTextSecondary = Color(0xFF8B9CA9);
  static const Color dashboardBorder = Color(0xFF3C4A57);
  static const Color dashboardGreen = Color(0xFF00C853);
  static const Color dashboardBlue = Color(0xFF2AABEE);
}
