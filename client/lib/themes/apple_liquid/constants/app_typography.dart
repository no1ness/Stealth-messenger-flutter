import 'package:flutter/material.dart';

/// Typography tokens for the Stealth design system.
///
/// Two families ship with the app (see `pubspec.yaml > fonts` and
/// `docs/design-system.md > Fonts`):
///
/// - **Geist** — body, UI labels, headings. Variable weight family
///   covering 400/500/600/700.
/// - **GeistMono** — numerics, identifiers, hashes, timestamps,
///   the in-call duration timer. The "feels like `openssl` output"
///   pair to Geist Sans. Weights 400/500/600.
///
/// Both are SIL Open Font License 1.1 from Vercel's
/// `vercel/geist-font` repository — no commercial licensing burden.
///
/// If a Geist face ever fails to load at runtime, Flutter falls back
/// to the [AppFontStacks] ladder (system sans-serif / system mono).
class AppTypography {
  AppTypography._();

  /// Body, UI, headings.
  static const String fontFamily = 'Geist';

  /// Numerics, identifiers, durations, hashes. Use anywhere the value
  /// is "data, not prose".
  static const String fontFamilyMono = 'GeistMono';

  // -- Large titles -------------------------------------------------

  static const TextStyle largeTitle = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
    height: 1.18,
  );

  // -- Titles -------------------------------------------------------

  static const TextStyle title1 = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.36,
    height: 1.21,
  );

  static const TextStyle title2 = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.35,
    height: 1.27,
  );

  static const TextStyle title3 = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.38,
    height: 1.25,
  );

  /// Large monospace title — used for the in-call duration timer and
  /// anywhere a "this is a value, not text" feel is wanted at title
  /// scale (e.g. a prominent safety-number readout).
  static const TextStyle titleMono = TextStyle(
    fontFamily: fontFamilyMono,
    fontFamilyFallback: AppFontStacks.monoFallbacks,
    fontSize: 28,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.36,
    height: 1.21,
  );

  // -- Headline / body ---------------------------------------------

  static const TextStyle headline = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
    height: 1.29,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
    height: 1.29,
  );

  static const TextStyle bodyEmphasis = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
    height: 1.29,
  );

  /// Monospace at body scale — for inline crypto strings, hashes, ids.
  static const TextStyle bodyMono = TextStyle(
    fontFamily: fontFamilyMono,
    fontFamilyFallback: AppFontStacks.monoFallbacks,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.31,
  );

  // -- Callout ------------------------------------------------------

  static const TextStyle callout = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.32,
    height: 1.31,
  );

  static const TextStyle calloutEmphasis = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.32,
    height: 1.31,
  );

  // -- Subheadline --------------------------------------------------

  static const TextStyle subheadline = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
    height: 1.33,
  );

  static const TextStyle subheadlineEmphasis = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.24,
    height: 1.33,
  );

  // -- Footnote -----------------------------------------------------

  static const TextStyle footnote = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    height: 1.38,
  );

  static const TextStyle footnoteEmphasis = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.08,
    height: 1.38,
  );

  // -- Caption ------------------------------------------------------

  static const TextStyle caption1 = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.33,
  );

  static const TextStyle caption1Emphasis = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.33,
  );

  /// Monospace caption — chat-bubble timestamps, micro-IDs.
  static const TextStyle captionMono = TextStyle(
    fontFamily: fontFamilyMono,
    fontFamilyFallback: AppFontStacks.monoFallbacks,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.33,
  );

  static const TextStyle caption2 = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.07,
    height: 1.36,
  );

  static const TextStyle caption2Emphasis = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: AppFontStacks.sansFallbacks,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.07,
    height: 1.36,
  );
}

/// Fallback font ladders.
///
/// If a Geist face fails to load at runtime — most commonly on web
/// before the asset is fetched, or in tests that did not call
/// `loadAppFonts()` from the golden harness — Flutter walks this list
/// in order. We aim for "looks close enough to keep layout from
/// shifting" rather than "looks identical".
class AppFontStacks {
  AppFontStacks._();

  /// Used by every non-mono style in [AppTypography].
  static const List<String> sansFallbacks = <String>[
    'system-ui',
    '-apple-system',
    'SF Pro Display',
    'SF Pro Text',
    'Roboto',
    'Segoe UI',
    'Liberation Sans',
    'sans-serif',
  ];

  /// Used by every mono style in [AppTypography]. Order chosen so
  /// platforms with a usable system mono kick in before we fall to
  /// generic `monospace`.
  static const List<String> monoFallbacks = <String>[
    'SF Mono',
    'Menlo',
    'Roboto Mono',
    'Consolas',
    'Liberation Mono',
    'monospace',
  ];
}
